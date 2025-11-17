FROM node:20

WORKDIR /app

# Copio solo package.json y lock para instalar dependencias
COPY package*.json ./

RUN npm install

# Copio el resto del proyecto al contenedor
COPY . .

EXPOSE 3000

CMD ["node", "app.js"]
