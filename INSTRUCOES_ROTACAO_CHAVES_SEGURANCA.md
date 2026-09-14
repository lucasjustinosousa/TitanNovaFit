# Instruções Operacionais: Rotação Obrigatória de Chaves de Segurança

> [!CAUTION]
> **AÇÃO MANUAL URGENTE EXIGIDA NO PAINEL SUPABASE E NA VERCEL**
> Chaves administrativas (`service_role`) estiveram anteriormente versionadas no repositório em texto plano e codificadas em Base64.
> Todos os arquivos locais foram corrigidos e o código agora depende estritamente de variáveis de ambiente. No entanto, por segurança máxima, **as chaves antigas devem ser imediatamente revogadas e rotacionadas**.

---

## Passo a Passo para o Administrador / Responsável

### 1. Rotacionar a Chave no Painel do Supabase
1. Acesse o console oficial do Supabase: [https://supabase.com/dashboard](https://supabase.com/dashboard).
2. Selecione o projeto do **TitanNova Fit**.
3. Navegue até **Project Settings** (ícone de engrenagem) > **API**.
4. Na seção **Project API Keys**, localize a chave `service_role` (secret).
5. Clique em **Rotate Key** (Rotacionar Chave).
6. Copie a **nova** chave `service_role` gerada e mantenha-a em local seguro (gestor de segredos). A chave antiga deixará de ter efeito imediatamente.

---

### 2. Atualizar as Variáveis de Ambiente na Vercel
1. Acesse o painel da **Vercel**: [https://vercel.com/dashboard](https://vercel.com/dashboard).
2. Selecione o projeto do **TitanNova Fit**.
3. Acesse **Settings** > **Environment Variables**.
4. Atualize (ou adicione, se ausente) as seguintes variáveis nos ambientes **Production**, **Preview** e **Development**:
   - `SUPABASE_URL`: URL oficial do projeto (ex.: `https://seu-id.supabase.co`).
   - `SUPABASE_SERVICE_ROLE_KEY`: A **nova** chave `service_role` rotacionada obtida no Passo 1.
5. Salve as alterações.

---

### 3. Verificação do Histórico Git
1. Recomenda-se realizar uma limpeza de histórico caso o repositório se torne público, utilizando ferramentas como `git-filter-repo` ou `BFG Repo-Cleaner` para expurgar commits passados que continham os hashes antigos.
2. Como a chave antiga será revogada no Supabase, mesmo que alguém consulte o histórico do commit anterior, a chave expirada será rejeitada pela API do Supabase com `401 Unauthorized`.

---

### 4. Redeploy na Vercel
1. O deploy na Vercel só deve ser promovido para produção **após** a rotação da chave no Supabase e a gravação do novo segredo na Vercel.
2. Ao realizar o push da branch `main` ou disparar um novo deploy na Vercel, as Serverless Functions (`/api/users`, `/api/subscriptions`, `/api/trainers`, `/api/legal`) passarão a operar com a chave atualizada e segura.
