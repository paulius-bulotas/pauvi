require('dotenv').config();

const express = require('express');
const mysql = require('mysql2/promise');

const app = express();
const port = Number(process.env.PORT || 3000);

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'pauvi',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'pauvi',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0
});

app.set('trust proxy', true);
app.use(express.json());

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    service: 'pauvi-backend'
  });
});

app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');

    res.json({
      ok: true,
      api: true,
      database: true
    });
  } catch (error) {
    console.error(error);

    res.status(503).json({
      ok: false,
      api: true,
      database: false
    });
  }
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Pauvi backend listening on ${port}`);
});
