'use strict'

const fs = require('fs')
const path = require('path')

const rootDir = path.resolve(__dirname, '..')
const packageJsonPath = path.join(rootDir, 'package.json')
const workspacePath = path.join(rootDir, 'pnpm-workspace.yaml')
const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'))
const dependencySections = [
  'dependencies',
  'devDependencies',
  'optionalDependencies',
  'peerDependencies'
]

const pinnedDependencies = dependencySections.flatMap(section => {
  return Object.entries(packageJson[section] || {})
    .filter(([, version]) => version !== 'latest')
    .map(([name, version]) => `${section}.${name}=${version}`)
})

const workspaceLines = fs.readFileSync(workspacePath, 'utf8').split(/\r?\n/)
const overridesStart = workspaceLines.findIndex(line => line === 'overrides:')
const invalidOverrides = []
const overrideLines = []

if (overridesStart !== -1) {
  for (const line of workspaceLines.slice(overridesStart + 1)) {
    if (line && !line.startsWith(' ')) break
    overrideLines.push(line)
    const match = line.match(/^  (?:'[^']+'|[^:#]+):\s*(\S+)\s*$/)
    if (!match) continue
    const value = match[1].replace(/^['"]|['"]$/g, '')
    if (value !== 'latest' && value !== '-') {
      invalidOverrides.push(line.trim())
    }
  }
}

if (pinnedDependencies.length > 0 || invalidOverrides.length > 0) {
  console.error('Every package declaration must use latest; overrides may only use latest or remove a package:')
  for (const dependency of [...pinnedDependencies, ...invalidOverrides]) {
    console.error(`- ${dependency}`)
  }
  process.exitCode = 1
} else {
  const dependencyCount = dependencySections.reduce((count, section) => {
    return count + Object.keys(packageJson[section] || {}).length
  }, 0)
  const overrideCount = overrideLines
    .filter(line => /^  (?:'[^']+'|[^:#]+):\s*\S+\s*$/.test(line))
    .length
  console.log(
    `All ${dependencyCount} package declarations use latest; ${overrideCount} overrides use latest or remove a package.`,
  )
}
