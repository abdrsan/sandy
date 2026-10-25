FROM node:22-alpine
WORKDIR /app
COPY --chown=node:node src ./src
RUN mkdir /data && chown node:node /data
USER node
ENV BIND=0.0.0.0 PORT=8787
EXPOSE 8787
CMD ["node","src/main.mjs"]
