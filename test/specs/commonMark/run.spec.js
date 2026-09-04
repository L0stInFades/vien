const specs = require('./commonmark.0.31.2.json')
const { runSpecRatchet } = require('../runSpecRatchet')

runSpecRatchet({
  label: 'CommonMark 0.31.2',
  specs,
})
