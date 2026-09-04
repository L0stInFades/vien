const specs = require('./gfm.0.29.json')
const { runSpecRatchet } = require('../runSpecRatchet')

runSpecRatchet({
  label: 'GFM 0.29',
  specs,
})
