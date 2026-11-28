FROM node:22 AS build
WORKDIR /w
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
FROM nginx:1.27-alpine
COPY --from=build /w/dist /usr/share/nginx/html
