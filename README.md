# Gestão de Projetos e Demandas TI — próxima etapa de integração

Destino informado: `https://github.com/neno-ti/gestao-projetos-demandas-ti.git` (branch `main`).
Supabase: `https://wbswlpjphmubobbazfkq.supabase.co`.

## Estado deste pacote

Este pacote reúne o HTML atual, a estrutura inicial Vite e a camada inicial Supabase (cliente, autenticação, funções de dados e migração SQL). **Ainda não é a integração final:** o JavaScript do HTML legado continua usando `localStorage` em projetos, usuários, status e DAILY. A troca desses pontos exige adaptação e testes de ponta a ponta antes de publicar.

## Estrutura

- `index.html`: versão atual do sistema, preservada sem alterações funcionais.
- `src/lib/supabaseClient.js`: cliente Supabase usando variáveis públicas.
- `src/lib/auth.js`: login, sessão e logout com Supabase Auth.
- `src/lib/data.js`: funções iniciais para iniciativas e DAILY.
- `supabase/migrations/202611140001_initial_schema.sql`: esquema inicial PostgreSQL, gatilhos, auditoria e RLS.
- `.env.example`: configuração local sem credenciais secretas.

## Próximos passos técnicos

1. No Supabase, obter a **publishable key** do projeto e configurar `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY` em `.env.local`.
2. Revisar e executar a migration no SQL Editor. Não aplicar em produção sem validar RLS com cada perfil.
3. Criar o primeiro usuário pelo Supabase Auth; elevar seu perfil para `Administrador` usando o UUID da conta em `public.profiles`.
4. Adaptar o HTML para carregar os módulos e substituir, de forma coordenada, `loadSavedProjects/persist`, `loadUsers/saveUsers`, `loadStatusData/persistStatuses` e `getDailyStore/saveDaily`.
5. Criar migração única dos dados locais: `projects[]` + `subs[]`, status/cores e pautas DAILY. Não importar as senhas de `projetos_ti_usuarios_v1`; criar/redefinir credenciais pelo Supabase Auth.
6. Implementar sincronização entre usuários, tratamento de falhas de rede e prevenção de sobrescrita concorrente.
7. Testar em Preview com pelo menos duas contas e quatro perfis antes de Production.

## Rodar localmente

```bash
npm install
cp .env.example .env.local
# editar .env.local e inserir a publishable key
npm run dev
```

## Segurança

- Apenas publishable key no browser; RLS obrigatória.
- Nunca versionar `.env.local`.
- Nunca usar `service_role`/secret key no frontend.
- Desabilitar cadastro público e provisionar usuários pela administração.
- O HTML ainda contém lógica legada de autenticação local e credencial administrativa fixa. Não disponibilizar o `index.html` atual publicamente antes de substituir esse login pelo Supabase Auth.

## Implantação no Vercel

- Framework preset: Vite / Other.
- Build command: `npm run build`.
- Output directory: `dist`.
- Environment variables (Production, Preview e Development): `VITE_SUPABASE_URL` e `VITE_SUPABASE_PUBLISHABLE_KEY`.
