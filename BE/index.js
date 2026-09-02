require('dotenv').config()

const express = require('express')
const helmet = require('helmet')
const mysql = require('mysql2/promise')

const app = express()
const port = Number(process.env.PORT || 3000)

app.disable('x-powered-by')
app.use(helmet())
app.use(express.json({ limit: '1mb' }))

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: Number(process.env.DB_PORT || 3306),
  database: process.env.DB_NAME || 'pauvi',
  user: process.env.DB_USER || 'pauvi',
  password: process.env.DB_PASSWORD || '',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  enableKeepAlive: true,
})

app.get('/health', (_req, res) => {
  res.json({ ok: true, service: 'pauvi-backend' })
})

app.get('/api/health', async (_req, res) => {
  try {
    await pool.query('SELECT 1')
    res.json({ ok: true, api: true, database: true })
  } catch (error) {
    console.error('Database health check failed:', error.message)
    res.status(503).json({ ok: false, api: true, database: false })
  }
})

app.use('/api', (_req, res) => {
  res.status(404).json({ error: 'API route not found' })
})

app.use((error, _req, res, _next) => {
  console.error(error)
  res.status(500).json({ error: 'Internal server error' })
})

const server = app.listen(port, '0.0.0.0', () => {
  console.log(`Pauvi backend listening on port ${port}`)
})

async function shutdown(signal) {
  console.log(`${signal} received, shutting down`)
  server.close(async () => {
    await pool.end().catch(() => {})
    process.exit(0)
  })
}

process.on('SIGTERM', () => shutdown('SIGTERM'))
process.on('SIGINT', () => shutdown('SIGINT'))
