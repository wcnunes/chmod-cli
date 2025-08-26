#!/usr/bin/env bash
# chmod-xcli — TUI/CLI para montar e aplicar comandos chmod
# Autor: Willian C. Nunes
# Licença: MIT
# Requisitos: bash 4+, coreutils (chmod, printf),
#   opcional: whiptail (ou dialog), xclip/pbcopy/wl-copy para copiar

set -euo pipefail

# -------------------------------
# Utilidades
# -------------------------------
VERSION="1.0.0"
SCRIPT_NAME="chmod-xcli"

err() { printf "\e[31m[erro]\e[0m %s\n" "$*" >&2; }
log() { printf "\e[36m[info]\e[0m %s\n" "$*" >&2; }
die() { err "$*"; exit 1; }

has() { command -v "$1" >/dev/null 2>&1; }

copy_clipboard() {
  local text="$1"
  if has xclip; then printf "%s" "$text" | xclip -sel clip; return 0; fi
  if has wl-copy; then printf "%s" "$text" | wl-copy; return 0; fi
  if has pbcopy; then printf "%s" "$text" | pbcopy; return 0; fi
  return 1
}

join_by() { local IFS="$1"; shift; echo "$*"; }

# -------------------------------
# Ajuda
# -------------------------------
usage() {
cat <<'USAGE'
chmod-xcli — constrói e aplica comandos `chmod` via CLI ou TUI.

USO RÁPIDO
  chmod-xcli                       # abre TUI (se whiptail/dialog presente)
  chmod-xcli --op + --classes ugo --perms rwx --apply -- ./*.sh
  chmod-xcli --octal 755 -R --apply -- /var/www/html

SINTAXE
  chmod-xcli [opções] [--] [ALVOS...]

OPÇÕES (CLI)
  --op {+, -, =}            Operação simbólica (add/remove/define)
  --classes CLS             Conjuntos: combinação de u,g,o,a (ex: ug, a)
  --perms PERMS             Permissões: combinação de r,w,x (ex: rx)
  --special LIST            Especiais: vírgula separada: suid,sgid,sticky
  --octal DDD               Modo octal (ex: 640 ou 4755). Ignora --op/--classes/--perms
  -R, --recursive           Aplica recursivamente
  --files-only              Restringe a arquivos (usa find)
  --dirs-only               Restringe a diretórios (usa find)
  -n, --dry-run             Apenas exibe o comando resultante
  -a, --apply               Executa o comando
  -p, --print               Imprime o comando (padrão)
  -c, --copy                Copia o comando para a área de transferência (se possível)
  --tui                     Força TUI
  -q, --quiet               Saída mínima
  -v, --version             Mostra versão
  -h, --help                Mostra ajuda

TUI (se whiptail/dialog estiver disponível)
  Permite escolher operação, classes, permissões, bits especiais, recursividade
  e alvos. Em seguida, exibe prévia e permite executar/copiar.

EXEMPLOS
  # Dar execução ao dono para scripts na pasta
  chmod-xcli --op + --classes u --perms x --apply -- *.sh

  # Definir 755 recursivo em um site e copiar o comando
  chmod-xcli --octal 755 -R -c -- /var/www/html

  # Remover escrita para outros em um arquivo específico (simbólico)
  chmod-xcli --op - --classes o --perms w -- file.txt

Notas:
  • Se usar filtros --files-only/--dirs-only com múltiplos alvos, o comando gerado
    utilizará `find` para preservar a intenção.
USAGE
}

# -------------------------------
# Construção de modo simbólico e octal
# -------------------------------
normalize_classes() {
  local c="$1"; c=${c//,/}
  [[ -z "$c" ]] && echo "a" && return
  # Remove duplicados preservando ordem u g o a
  local out="" seen_u=0 seen_g=0 seen_o=0 seen_a=0 ch
  for ch in $(echo "$c" | sed -E 's/(.)/\1\n/g'); do
    case "$ch" in
      u) [[ $seen_u -eq 0 ]] && out+="u" && seen_u=1 ;;
      g) [[ $seen_g -eq 0 ]] && out+="g" && seen_g=1 ;;
      o) [[ $seen_o -eq 0 ]] && out+="o" && seen_o=1 ;;
      a) [[ $seen_a -eq 0 ]] && out+="a" && seen_a=1 ;;
    esac
  done
  [[ -z "$out" ]] && out="a"
  echo "$out"
}

normalize_perms() {
  local p="$1"; p=${p//,/}
  local out="" seen_r=0 seen_w=0 seen_x=0
  local ch
  for ch in $(echo "$p" | sed -E 's/(.)/\1\n/g'); do
    case "$ch" in
      r) [[ $seen_r -eq 0 ]] && out+="r" && seen_r=1 ;;
      w) [[ $seen_w -eq 0 ]] && out+="w" && seen_w=1 ;;
      x) [[ $seen_x -eq 0 ]] && out+="x" && seen_x=1 ;;
    esac
  done
  echo "$out"
}

build_symbolic_mode() {
  local op="$1" classes="$2" perms="$3" special_list="$4"
  classes=$(normalize_classes "$classes")
  perms=$(normalize_perms "$perms")

  [[ "$op" =~ ^[+\-=]$ ]] || die "--op deve ser um de: + - ="
  [[ -n "$perms" || -n "$special_list" ]] || die "--perms ou --special obrigatório"

  local specials=""
  IFS=, read -r -a sp <<< "${special_list,,}"
  for s in "${sp[@]:-}"; do
    case "$s" in
      suid) specials+="u+s";;
      sgid) specials+="g+s";;
      sticky) specials+="+t";; # aplicar para 'a'
      "" ) ;;
      *) die "special inválido: $s (use suid,sgid,sticky)" ;;
    esac
  done

  local mode=""
  if [[ -n "$perms" ]]; then
    mode+="${classes}${op}${perms}"
  fi
  if [[ -n "$specials" ]]; then
    # specials aplicados com +; quando op for '=', aplicamos em etapa adicional
    if [[ "$op" == "=" && -n "$perms" ]]; then
      mode+=",$specials"
    else
      # se não há perms, ainda precisamos indicar alvo; usar 'a'
      local target="$classes"; [[ -z "$target" ]] && target="a"
      [[ -n "$mode" ]] && mode+=";"
      mode+="${target}${specials}"
    fi
  fi
  echo "$mode"
}

valid_octal() { [[ "$1" =~ ^[0-7]{3,4}$ ]]; }

# -------------------------------
# Gerar comando final
# -------------------------------
quote_path() { printf '"%s"' "$1" | sed 's/\n/\\n/g'; }

build_command() {
  local recursive="$1" files_only="$2" dirs_only="$3" mode="$4" octal="$5"; shift 5
  local paths=("$@")

  [[ ${#paths[@]} -gt 0 ]] || die "Nenhum alvo informado. Passe caminhos ou use a TUI."
  local chmod_args=()
  [[ "$recursive" == 1 ]] && chmod_args+=("-R")

  local mode_arg
  if [[ -n "$octal" ]]; then
    mode_arg="$octal"
  else
    mode_arg="$mode"
  fi

  if [[ "$files_only" == 1 || "$dirs_only" == 1 ]]; then
    # Usar find para respeitar filtros
    local typeflag=""
    [[ "$files_only" == 1 ]] && typeflag="-type f"
    [[ "$dirs_only" == 1 ]] && typeflag="-type d"

    local pieces=()
    for p in "${paths[@]}"; do
      pieces+=("find" "$(printf '%q' "$p")" "${typeflag}" "-exec" "chmod" "${chmod_args[@]}" "$(printf '%q' "$mode_arg")" "{}" "+")
      pieces+=(";")
    done
    printf "%s\n" "$(join_by ' ' "${pieces[@]}")" | sed 's/ ;$//' # remove ; final
  else
    local qpaths=()
    for p in "${paths[@]}"; do qpaths+=("$(printf '%q' "$p")"); done
    printf "chmod %s %s -- %s\n" "${chmod_args[*]}" "$(printf '%q' "$mode_arg")" "${qpaths[*]}"
  fi
}

# -------------------------------
# Execução segura
# -------------------------------
maybe_apply() {
  local cmd="$1" dry="$2" apply="$3" quiet="$4" copy="$5"
  [[ "$quiet" -ne 1 ]] && echo "$cmd"
  if [[ "$copy" -eq 1 ]]; then
    if copy_clipboard "$cmd"; then [[ "$quiet" -ne 1 ]] && log "Comando copiado para a área de transferência."; else err "Não foi possível copiar (xclip/wl-copy/pbcopy ausente)."; fi
  fi
  if [[ "$dry" -eq 1 && "$apply" -eq 1 ]]; then die "--dry-run e --apply são mutuamente exclusivos"; fi
  if [[ "$apply" -eq 1 ]]; then eval "$cmd"; fi
}

# -------------------------------
# TUI com whiptail/dialog
# -------------------------------
have_tui() { has whiptail || has dialog; }
wt() {
  # wrapper simples: usa whiptail se existir, senão dialog
  local bin
  if has whiptail; then bin=whiptail; else bin=dialog; fi
  "$bin" "$@"
}

run_tui() {
  have_tui || die "TUI requer whiptail ou dialog instalado. Use o modo CLI."

  local height=20 width=70 menuh=10

  local op
  op=$(wt --title "$SCRIPT_NAME" --menu "Operação" $height $width $menuh \
      "+" "Adicionar (+)" \
      "-" "Remover (-)" \
      "=" "Definir (=)" 3>&1 1>&2 2>&3) || exit 1

  local classes sel
  sel=$(wt --title "$SCRIPT_NAME" --checklist "Selecione classes (u/g/o/a)" $height $width $menuh \
      u "user" ON \
      g "group" OFF \
      o "others" OFF \
      a "all" OFF 3>&1 1>&2 2>&3) || exit 1
  classes=$(echo "$sel" | tr -d '" ')
  [[ -z "$classes" ]] && classes="u"

  local perms
  sel=$(wt --title "$SCRIPT_NAME" --checklist "Permissões" $height $width $menuh \
      r "read" ON \
      w "write" OFF \
      x "execute" OFF 3>&1 1>&2 2>&3) || exit 1
  perms=$(echo "$sel" | tr -d '" ')

  local specials
  sel=$(wt --title "$SCRIPT_NAME" --checklist "Bits especiais (opcional)" $height $width $menuh \
      suid   "setuid (u+s / 4---)" OFF \
      sgid   "setgid (g+s / -2--)" OFF \
      sticky "sticky (t / --1-)" OFF 3>&1 1>&2 2>&3) || exit 1
  specials=$(echo "$sel" | tr -d '" ' | tr ' ' ',')

  local recursive_choice
  recursive_choice=$(wt --title "$SCRIPT_NAME" --yesno "Aplicar recursivamente?" 8 60; echo $?)
  local recursive=0; [[ "$recursive_choice" -eq 0 ]] && recursive=1

  local scope
  scope=$(wt --title "$SCRIPT_NAME" --menu "Alvos (escopo)" 12 60 4 \
      all "Arquivos e diretórios" \
      files "Somente arquivos" \
      dirs "Somente diretórios" 3>&1 1>&2 2>&3) || exit 1
  local files_only=0 dirs_only=0
  [[ "$scope" == files ]] && files_only=1
  [[ "$scope" == dirs ]] && dirs_only=1

  local paths
  paths=$(wt --title "$SCRIPT_NAME" --inputbox "Informe os alvos (globs separados por espaço)" 10 70 "./*" 3>&1 1>&2 2>&3) || exit 1
  # Montar modo simbólico
  local mode symbolicCmd
  mode=$(build_symbolic_mode "$op" "$classes" "$perms" "$specials")
  IFS=' ' read -r -a arr_paths <<< "$paths"
  symbolicCmd=$(build_command "$recursive" "$files_only" "$dirs_only" "$mode" "" "${arr_paths[@]}")

  # Alternativa: permitir octal
  local use_octal
  use_octal=$(wt --title "$SCRIPT_NAME" --yesno "Deseja usar OCTAL em vez de simbólico?" 8 60; echo $?)
  if [[ "$use_octal" -eq 0 ]]; then
    local octal
    octal=$(wt --title "$SCRIPT_NAME" --inputbox "Digite octal (ex: 755, 640, 4755)" 10 40 "755" 3>&1 1>&2 2>&3) || exit 1
    valid_octal "$octal" || die "Octal inválido: $octal"
    symbolicCmd=$(build_command "$recursive" "$files_only" "$dirs_only" "" "$octal" "${arr_paths[@]}")
  fi

  # Prévia e ação
  wt --title "$SCRIPT_NAME — Prévia" --msgbox "${symbolicCmd//\"/\' }" 12 70
  local action
  action=$(wt --title "$SCRIPT_NAME" --menu "O que deseja fazer?" 12 60 4 \
      print "Apenas imprimir" \
      copy  "Copiar para a área de transferência" \
      apply "Executar agora" 3>&1 1>&2 2>&3) || exit 1

  case "$action" in
    print) maybe_apply "$symbolicCmd" 0 0 0 0 ;;
    copy)  maybe_apply "$symbolicCmd" 0 0 0 1 ;;
    apply) maybe_apply "$symbolicCmd" 0 1 0 0 ;;
  esac
}

# -------------------------------
# Parser de argumentos
# -------------------------------
main() {
  local op="+" classes="u" perms="r" specials="" octal="" recursive=0 files_only=0 dirs_only=0
  local dry=0 apply=0 print=1 copy=0 quiet=0 force_tui=0
  local -a paths=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --op) op="$2"; shift 2 ;;
      --classes) classes="$2"; shift 2 ;;
      --perms) perms="$2"; shift 2 ;;
      --special) specials="$2"; shift 2 ;;
      --octal) octal="$2"; shift 2 ;;
      -R|--recursive) recursive=1; shift ;;
      --files-only) files_only=1; shift ;;
      --dirs-only) dirs_only=1; shift ;;
      -n|--dry-run) dry=1; shift ;;
      -a|--apply) apply=1; shift ;;
      -p|--print) print=1; shift ;;
      -c|--copy) copy=1; shift ;;
      --tui) force_tui=1; shift ;;
      -q|--quiet) quiet=1; shift ;;
      -v|--version) echo "$SCRIPT_NAME v$VERSION"; exit 0 ;;
      -h|--help) usage; exit 0 ;;
      --) shift; while [[ $# -gt 0 ]]; do paths+=("$1"); shift; done ;;
      -*) err "Opção desconhecida: $1"; echo; usage; exit 2 ;;
      *) paths+=("$1"); shift ;;
    esac
  done

  if [[ $force_tui -eq 1 || ( ${#paths[@]} -eq 0 && $(have_tui; echo $?) -eq 0 ) ]]; then
    run_tui
    exit $?
  fi

  # CLI
  local mode="" cmd
  if [[ -n "$octal" ]]; then
    valid_octal "$octal" || die "Octal inválido: $octal"
    cmd=$(build_command "$recursive" "$files_only" "$dirs_only" "" "$octal" "${paths[@]}")
  else
    mode=$(build_symbolic_mode "$op" "$classes" "$perms" "$specials")
    cmd=$(build_command "$recursive" "$files_only" "$dirs_only" "$mode" "" "${paths[@]}")
  fi

  maybe_apply "$cmd" "$dry" "$apply" "$quiet" "$copy"
}

main "$@"
