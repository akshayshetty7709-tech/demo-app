FROM node:20-alpine
WORKDIR /app
ENV PORT=3000
COPY package.json server.js VERSION ./
EXPOSE 3000
USER node
HEALTHCHECK --interval=15s --timeout=3s --retries=5 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1
CMD ["node", "server.js"]
