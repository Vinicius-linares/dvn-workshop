const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;

app.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.get('/', (_req, res) => {
  res.status(200).send('Hello from the fixture app');
});

app.listen(PORT, () => {
  console.log(`fixture app listening on ${PORT}`);
});
