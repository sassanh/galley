import { defineConfig } from 'vitepress'

const githubRepository = process.env.GITHUB_REPOSITORY || 'sassanh/galley'
const githubServerUrl = process.env.GITHUB_SERVER_URL || 'https://codeberg.org'
const isGitHub = githubServerUrl.includes('github.com')

const socialLink = isGitHub
  ? { icon: 'github', link: `https://github.com/${githubRepository}` }
  : { icon: 'codeberg', link: `https://codeberg.org/${githubRepository}` }

export default defineConfig({
  title: 'Galley Compiler',
  description: 'Documentation for the Sanbus Galley parser generators and compiler.',
  base: '/galley/',
  themeConfig: {
    nav: [
      { text: 'Home', link: '/' },
      { text: 'Documentation', link: '/getting_started' }
    ],
    sidebar: [
      {
        text: 'Introduction',
        items: [
          { text: 'Getting Started', link: '/getting_started' },
          { text: 'Included Languages', link: '/languages' },
          { text: 'Configuration & Flags', link: '/configuration' }
        ]
      },
      {
        text: 'User Guide',
        items: [
          { text: 'Writing a Language', link: '/writing_a_language' },
          { text: 'Grammar Guidelines', link: '/grammar_guidelines' },
          { text: 'Reduction Procedures', link: '/procedures' }
        ]
      },
      {
        text: 'Advanced Architecture & Performance',
        items: [
          { text: 'Core Architecture', link: '/architecture' },
          { text: 'AST Node Allocations', link: '/ast_node_allocations' },
          { text: 'Benchmarks', link: '/benchmarks' }
        ]
      }
    ],
    socialLinks: [
      socialLink
    ]
  },
  vite: {
    server: {
      fs: {
        allow: ['..']
      }
    }
  }
})
