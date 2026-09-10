# Diretrizes do Projeto TitanNova Fit

## Commit e Deploy Automático (Regra Permanente)
- Sempre que concluir alterações, correções ou melhorias solicitadas e aprovadas pelo usuário, execute o fluxo completo de commit e sincronização com o repositório remoto:
  1. `git add .` (ou adicionar os arquivos alterados, respeitando o `.gitignore`).
  2. `git commit -m "<mensagem clara e contextualizada>"`.
  3. `git push origin main` imediatamente para sincronizar com o GitHub e acionar o deploy contínuo na Vercel.
- Não deixe commits pendentes localmente sem envio, a menos que haja erro explícito ou instrução contrária do usuário.
