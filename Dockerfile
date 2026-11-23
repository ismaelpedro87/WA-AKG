
# ==========================================
# BUILDER
# ==========================================
FROM node:26-alpine AS builder

RUN apk add --no-cache openssl ca-certificates

WORKDIR /app

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# Variáveis de fallback para o build
ENV DATABASE_URL="mysql://build_user:build_pass@localhost:3306/wa_akg"
ENV AUTH_SECRET="build_secret_must_be_at_least_32_characters_long_for_nextjs"
ENV NEXTAUTH_SECRET="build_secret_must_be_at_least_32_characters_long_for_nextjs"

# ==========================================
# DEPENDENCIES
# ==========================================

COPY package*.json ./
COPY prisma ./prisma/

# IMPORTANTE:
# NODE_ENV=production normalmente faz o npm omitir devDependencies.
# --include=dev garante a instalação do Prisma CLI 5.
RUN npm ci --include=dev --legacy-peer-deps \
    && npm cache clean --force

# ==========================================
# SOURCE & BUILD
# ==========================================

COPY . .

# Usa exclusivamente o Prisma instalado no projeto
RUN ./node_modules/.bin/prisma --version

RUN ./node_modules/.bin/prisma generate

# Build Next.js
RUN npm run build

# ==========================================
# PREPARE RUNTIME DEPENDENCIES
# ==========================================

# Remove dependências exclusivamente de desenvolvimento
RUN npm prune --omit=dev

# Instala tsx para executar o servidor TypeScript
RUN npm install --no-save --package-lock=false tsx@4.21.0


# ==========================================
# PRODUCTION
# ==========================================
FROM node:26-alpine AS runner

RUN apk add --no-cache openssl ca-certificates

WORKDIR /app

COPY --from=builder --chown=node:node /app/package*.json ./
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/.next ./.next
COPY --from=builder --chown=node:node /app/src ./src
COPY --from=builder --chown=node:node /app/prisma ./prisma
COPY --from=builder --chown=node:node /app/public ./public
COPY --from=builder --chown=node:node /app/tsconfig.json ./
COPY --from=builder --chown=node:node /app/next.config.ts ./
COPY --from=builder --chown=node:node /app/scripts ./scripts

# Diretórios persistentes
RUN mkdir -p /app/data/media /app/data/auth /app/uploads \
    && chown -R node:node /app/data /app/uploads

USER node

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

EXPOSE 3000

CMD ["sh", "-c", "node_modules/.bin/prisma db push && (if [ -n \"$ADMIN_EMAIL\" ] && [ -n \"$ADMIN_PASSWORD\" ]; then node scripts/setup-admin.js \"$ADMIN_EMAIL\" \"$ADMIN_PASSWORD\"; fi) && node node_modules/tsx/dist/cli.mjs src/server/index.ts"]
