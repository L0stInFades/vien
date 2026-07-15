import { createRouter, createWebHashHistory } from 'vue-router'
import App from '@/pages/app'
import Preference from '@/pages/preference'
import General from '@/prefComponents/general'
import Editor from '@/prefComponents/editor'
import Markdown from '@/prefComponents/markdown'
import SpellChecker from '@/prefComponents/spellchecker'
import Theme from '@/prefComponents/theme'
import Image from '@/prefComponents/image'
import Keybindings from '@/prefComponents/keybindings'

const SETTINGS_CATEGORIES = new Set(['general', 'editor', 'markdown', 'spelling', 'theme', 'image', 'keybindings'])

const parseSettingsPage = (type) => {
  const match = /^settings\/([^/]+)$/.exec(type)
  const category = match?.[1]

  if (category && SETTINGS_CATEGORIES.has(category)) {
    return `/preference/${category}`
  }

  return '/preference'
}

const routes = (type) =>
  createRouter({
    history: createWebHashHistory(),
    routes: [
      {
        path: '/',
        redirect: type === 'editor' ? '/editor' : parseSettingsPage(type),
      },
      {
        path: '/editor',
        component: App,
      },
      {
        path: '/preference',
        component: Preference,
        children: [
          {
            path: '',
            component: General,
          },
          {
            path: 'general',
            component: General,
            name: 'general',
          },
          {
            path: 'editor',
            component: Editor,
            name: 'editor',
          },
          {
            path: 'markdown',
            component: Markdown,
            name: 'markdown',
          },
          {
            path: 'spelling',
            component: SpellChecker,
            name: 'spelling',
          },
          {
            path: 'theme',
            component: Theme,
            name: 'theme',
          },
          {
            path: 'image',
            component: Image,
            name: 'image',
          },
          {
            path: 'keybindings',
            component: Keybindings,
            name: 'keybindings',
          },
        ],
      },
    ],
  })

export default routes
