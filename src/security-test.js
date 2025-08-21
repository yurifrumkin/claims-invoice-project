// Test file for security scanning - contains intentional issues
const express = require('express');
const app = express();

// Issue 1: SQL Injection vulnerability
app.get('/claims/:id', (req, res) => {
    const claimId = req.params.id;
    const query = `SELECT * FROM claims WHERE id = ${claimId}`;
    // This concatenates user input directly - security risk
    database.query(query, (err, results) => {
        res.json(results);
    });
});

// Issue 2: Hardcoded secret
const DATABASE_PASSWORD = "admin123";

// Issue 3: No input validation
app.post('/process-claim', (req, res) => {
    const data = req.body;
    processClaimData(data); // No validation of input
    res.send('Processed');
});

// Issue 4: Another security problem for testing
app.get('/admin', (req, res) => {
    // No authentication check on admin endpoint
    res.json({ sensitive: 'admin data' });
});

module.exports = app;