# chmod-xcli

**chmod-xcli** é uma ferramenta **TUI e CLI** que simplifica a criação e execução de comandos `chmod`. Ela fornece uma interface amigável no terminal (via **whiptail** ou **dialog**) que permite selecionar permissões de forma visual, além de oferecer suporte completo a parâmetros via linha de comando.

Ideal para administradores de sistemas, desenvolvedores e estudantes que desejam **rapidez e precisão** ao gerenciar permissões de arquivos e diretórios em sistemas tipo Unix.

---

## ✨ Recursos principais
- **TUI (Text User Interface):** seleção interativa de operações, classes, permissões, bits especiais e escopo (arquivos, diretórios ou ambos).
- **CLI completa:** construa comandos `chmod` de forma programática via opções.
- **Bits especiais:** suporte a `suid`, `sgid` e `sticky bit`.
- **Filtros de escopo:** aplicar permissões apenas em arquivos ou apenas em diretórios.
- **Recursividade:** suporte ao parâmetro `-R`.
- **Pré-visualização do comando:** veja o que será executado antes de aplicar.
- **Execução segura:** escolha entre apenas imprimir, copiar para a área de transferência ou aplicar diretamente.
- **Modo Octal e Simbólico:** flexível para diferentes cenários.
- **Compatibilidade com clipboard:** suporta `xclip`, `wl-copy` ou `pbcopy` para copiar o comando gerado.

---

## 🚀 Instalação

Clone o repositório e instale o script em `/usr/local/bin`:

```bash
git clone https://github.com/wcnunes/chmod-cli.git
cd chmod-xcli
sudo install -m 0755 chmod-xcli /usr/local/bin/chmod-xcli
```

### Dependências opcionais
```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y whiptail   # ou dialog
sudo apt-get install -y xclip      # para copiar para o clipboard
```

---

## 🔧 Uso

### Modo TUI
Basta rodar:
```bash
chmod-xcli
```

Você poderá navegar por menus interativos para definir permissões.

### Modo CLI
```bash
# Dar permissão de execução ao dono em todos os scripts
chmod-xcli --op + --classes u --perms x --apply -- *.sh

# Definir 755 recursivo em um diretório e copiar o comando
chmod-xcli --octal 755 -R -c -- /var/www/html

# Remover escrita para outros em um arquivo
chmod-xcli --op - --classes o --perms w -- file.txt
```

---

## 📖 Opções principais
- `--op {+, -, =}` → Operação simbólica
- `--classes ugoa` → Classes (usuário, grupo, outros, todos)
- `--perms rwx` → Permissões
- `--special suid,sgid,sticky` → Bits especiais
- `--octal DDD` → Definir permissões em octal
- `-R, --recursive` → Aplicar recursivamente
- `--files-only` / `--dirs-only` → Restringir escopo
- `-a, --apply` → Executar imediatamente
- `-c, --copy` → Copiar comando para clipboard
- `-n, --dry-run` → Apenas mostrar comando
- `--tui` → Forçar modo TUI

---

## 📂 Exemplos práticos

```bash
# Transformar todos scripts em executáveis
chmod-xcli --op + --classes u --perms x --apply -- *.sh

# Definir permissões padrão de um site
chmod-xcli --octal 755 -R --apply /var/www/html

# Aplicar permissões recursivamente apenas em diretórios
chmod-xcli --op + --classes g --perms x --dirs-only -R -- /data/projects
```

---

## 🛡️ Segurança
O **chmod-xcli** nunca executa comandos sem confirmação. Você pode escolher entre:
- Apenas imprimir
- Copiar para clipboard
- Executar imediatamente

---

## 📌 Roadmap
- [ ] Exibir permissões atuais antes/depois (`stat`)
- [ ] Templates prontos de permissões comuns
- [ ] Suporte multilíngue (pt-BR/EN)
- [ ] Pacote `.deb` para fácil instalação

---

## 📜 Licença

Este projeto é distribuído sob a licença **MIT**.
