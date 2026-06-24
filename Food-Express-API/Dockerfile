FROM node:18-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=7000

COPY package*.json ./

RUN npm ci --omit=dev && npm cache clean --force

COPY . .

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

USER appuser

EXPOSE 7000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD wget -qO- http://127.0.0.1:7000/health || exit 1

CMD ["npm", "start"]