const { HtmlDiffer } = require('@markedjs/html-differ')
const { MT_MARKED_OPTIONS } = require('./config')
const { removeCustomClass } = require('./help')
const marked = require('../../src/muya/lib/parser/marked/index.ts').default

const htmlDiffer = new HtmlDiffer({
  ignoreSelfClosingSlash: true,
  ignoreAttributes: ['id', 'class'],
})

const validateSpecs = (label, specs) => {
  if (!Array.isArray(specs) || specs.length === 0) {
    throw new TypeError(`${label}: expected a non-empty spec fixture`)
  }

  const examples = new Set()

  for (const spec of specs) {
    if (!Number.isInteger(spec.example) || examples.has(spec.example)) {
      throw new TypeError(`${label}: example identifiers must be unique integers`)
    }
    if (typeof spec.section !== 'string' || typeof spec.markdown !== 'string' || typeof spec.html !== 'string') {
      throw new TypeError(`${label}: example ${spec.example} is malformed`)
    }
    if (spec.shouldFail !== undefined && spec.shouldFail !== true) {
      throw new TypeError(`${label}: example ${spec.example} has an invalid shouldFail marker`)
    }

    examples.add(spec.example)
  }
}

const formatExamples = (specs) => specs.map(({ example, section }) => `${example} (${section})`).join(', ')

const runSpecRatchet = ({ label, specs }) => {
  validateSpecs(label, specs)

  const approvedFailures = new Set(specs.filter(({ shouldFail }) => shouldFail).map(({ example }) => example))
  const currentFailures = []

  for (const spec of specs) {
    try {
      const actualHtml = removeCustomClass(marked(spec.markdown, MT_MARKED_OPTIONS))
      if (!htmlDiffer.isEqual(actualHtml, spec.html)) {
        currentFailures.push(spec)
      }
    } catch (error) {
      currentFailures.push({ ...spec, parserError: error })
    }
  }

  const currentFailureIds = new Set(currentFailures.map(({ example }) => example))
  const regressions = currentFailures.filter(({ example }) => !approvedFailures.has(example))
  const recoveries = specs.filter(({ example, shouldFail }) => shouldFail && !currentFailureIds.has(example))
  const knownLimitations = currentFailures.length - regressions.length
  const passing = specs.length - currentFailures.length

  console.log(
    `${label}: ${passing}/${specs.length} pass; ${knownLimitations} known limitations; ${regressions.length} new regressions`,
  )

  if (recoveries.length > 0) {
    console.log(`${label}: ${recoveries.length} approved failures now pass: ${formatExamples(recoveries)}`)
  }

  if (regressions.length > 0) {
    const parserErrors = regressions
      .filter(({ parserError }) => parserError)
      .map(({ example, parserError }) => `example ${example}: ${parserError.message}`)
    const errorDetails = parserErrors.length > 0 ? `\nParser errors:\n${parserErrors.join('\n')}` : ''

    throw new Error(`${label}: unapproved failures: ${formatExamples(regressions)}${errorDetails}`)
  }
}

module.exports = {
  runSpecRatchet,
}
