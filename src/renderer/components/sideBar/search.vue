<template>
    <div
      class="side-bar-search"
    >
      <div class="search-wrapper">
        <input
          type="text" v-model="keyword"
          placeholder="Search in folder..."
          @keyup="search"
        >
        <div class="controls">
          <span
            title="Case Sensitive"
            class="is-case-sensitive"
            :class="{'active': isCaseSensitive}"
            @click.stop="caseSensitiveClicked()"
          >
            <svg :viewBox="FindCaseIcon.viewBox" aria-hidden="true">
              <use :xlink:href="FindCaseIcon.url" />
            </svg>
          </span>
          <span
            title="Select whole word"
            class="is-whole-word"
            :class="{'active': isWholeWord}"
            @click.stop="wholeWordClicked()"
          >
            <svg :viewBox="FindWordIcon.viewBox" aria-hidden="true">
              <use :xlink:href="FindWordIcon.url" />
            </svg>
          </span>
          <span
            title="Use query as RegEx"
            class="is-regex"
            :class="{'active': isRegexp}"
            @click.stop="regexpClicked()"
          >
            <svg :viewBox="FindRegexIcon.viewBox" aria-hidden="true">
              <use :xlink:href="FindRegexIcon.url" />
            </svg>
          </span>
        </div>
      </div>

      <div class="search-status" v-if="showNoFolderOpenedMessage">
        <p>Open a folder to search its notes.</p>
        <button
          class="button-primary"
          @click="openFolder"
        >
          Open Folder
        </button>
      </div>
      <div class="search-status error" v-else-if="searchErrorString">{{ searchErrorString }}</div>
      <div class="search-status" v-else-if="showNoResultFoundMessage">No results for “{{ keyword }}”.</div>

      <div
        class="cancel-area"
        v-show="showSearchCancelArea"
      >
        <el-button
          type="primary"
          size="mini"
          @click="cancelSearcher"
        >
          Cancel <i class="el-icon-video-pause"></i>
        </el-button>
      </div>
      <div v-if="searchResult.length" class="search-result-info">{{searchResultInfo}}</div>
      <div class="search-result" v-if="searchResult.length">
        <search-result-item
          v-for="(item, index) of searchResult"
          :key="index"
          :searchResult="item"
        ></search-result-item>
      </div>
    </div>
</template>

<script>
import { mapState } from 'vuex'
import bus from '../../bus'
import log from 'electron-log'
import SearchResultItem from './searchResultItem.vue'
import { RipgrepDirectorySearcher } from '@/services/searchClient'
import FindCaseIcon from '@/assets/icons/searchIcons/iconCase.svg'
import FindWordIcon from '@/assets/icons/searchIcons/iconWord.svg'
import FindRegexIcon from '@/assets/icons/searchIcons/iconRegex.svg'
import { MARKDOWN_INCLUSIONS } from '../../../common/filesystem/paths'

export default {
  data() {
    this.lastKeyword = ''
    this.lastSearchTime = new Date()
    this.keyUpTimer = null
    this.searcherCancelCallback = null
    this.ripgrepDirectorySearcher = new RipgrepDirectorySearcher()
    this.FindCaseIcon = FindCaseIcon
    this.FindWordIcon = FindWordIcon
    this.FindRegexIcon = FindRegexIcon
    return {
      keyword: '',
      searchResult: [],
      searcherRunning: false,
      hasSearched: false,
      showSearchCancelArea: false,
      searchErrorString: '',

      isCaseSensitive: false,
      isWholeWord: false,
      isRegexp: false,
    }
  },
  components: {
    SearchResultItem,
  },
  watch: {
    showSideBar: function (value, oldValue) {
      if (value && !oldValue && this.rightColumn === 'search') {
        this.keyword = this.searchMatches.value
      }
    },
  },
  created() {
    this.$nextTick(() => {
      this.keyword = this.searchMatches.value
      bus.on('findInFolder', this.handleFindInFolder)
      if (this.keyword.length > 0 && this.searcherRunning === false) {
        this.searcherRunning = true
        this.search()
      }
    })
  },
  computed: {
    ...mapState({
      rightColumn: (state) => state.layout.rightColumn,
      showSideBar: (state) => state.layout.showSideBar,
      searchMatches: (state) => state.editor.currentFile.searchMatches,
      projectTree: (state) => state.project.projectTree,
      searchExclusions: (state) => state.preferences.searchExclusions,
      searchMaxFileSize: (state) => state.preferences.searchMaxFileSize,
      searchIncludeHidden: (state) => state.preferences.searchIncludeHidden,
      searchNoIgnore: (state) => state.preferences.searchNoIgnore,
      searchFollowSymlinks: (state) => state.preferences.searchFollowSymlinks,
    }),
    searchResultInfo() {
      const fileCount = this.searchResult.length
      const matchCount = this.searchResult.reduce((acc, item) => {
        return acc + item.matches.length
      }, 0)

      return `${matchCount} ${matchCount > 1 ? 'matches' : 'match'} in ${fileCount} ${fileCount > 1 ? 'files' : 'file'}`
    },
    showNoFolderOpenedMessage() {
      return !this.projectTree || !this.projectTree.pathname
    },
    showNoResultFoundMessage() {
      return (
        this.hasSearched && this.searchResult.length === 0 && this.searcherRunning === false && this.keyword.length > 0
      )
    },
  },
  methods: {
    search() {
      // No root directory is opened.
      if (this.showNoFolderOpenedMessage) {
        return
      }

      const { pathname: rootDirectoryPath } = this.projectTree
      const {
        keyword,
        searcherRunning,
        searcherCancelCallback,
        isCaseSensitive,
        isWholeWord,
        isRegexp,
        ripgrepDirectorySearcher,
      } = this

      if (searcherRunning && searcherCancelCallback) {
        searcherCancelCallback()
      }

      this.searchErrorString = ''
      this.searcherCancelCallback = null

      if (!keyword) {
        this.searchResult = []
        this.searcherRunning = false
        this.hasSearched = false
        return
      }

      let canceled = false
      this.searcherRunning = true
      this.hasSearched = true
      this.startShowSearchCancelAreaTimer()

      const newSearchResult = []
      const promises = ripgrepDirectorySearcher
        .search([rootDirectoryPath], keyword, {
          didMatch: (searchResult) => {
            if (canceled) return

            // filePath: "<file>"
            // matches: Array(1)
            // 0:
            //   leadingContextLines: []
            //   lineText: "foo-test"
            //   matchText: "foo"
            //   range: Array(2)
            //     0: (2) [0, 0]
            //     1: (2) [0, 3]
            //   length: 2
            //   trailingContextLines: []

            newSearchResult.push(searchResult)
          },
          didSearchPaths: (numPathsFound) => {
            // More than 100 files with (multiple) matches were found.
            if (!canceled && numPathsFound > 100) {
              canceled = true
              if (promises.cancel) {
                promises.cancel()
              }
              this.searchErrorString = 'Search was limited to 100 files.'
            }
          },

          // UI options
          isCaseSensitive,
          isWholeWord,
          isRegexp,

          // Options loaded from settings
          exclusions: this.searchExclusions,
          maxFileSize: this.searchMaxFileSize || null,
          includeHidden: this.searchIncludeHidden,
          noIgnore: this.searchNoIgnore,
          followSymlinks: this.searchFollowSymlinks,

          // Only search markdown files
          inclusions: MARKDOWN_INCLUSIONS,
        })
        .then(() => {
          this.searchResult = newSearchResult
          this.searcherRunning = false
          this.searcherCancelCallback = null
          this.stopShowSearchCancelAreaTimer()
        })
        .catch((err) => {
          canceled = true
          if (promises.cancel) {
            promises.cancel()
          }
          this.searcherRunning = false
          this.searcherCancelCallback = null
          this.stopShowSearchCancelAreaTimer()

          this.searchErrorString = err.message
          log.error(err)
        })

      this.searcherCancelCallback = () => {
        this.stopShowSearchCancelAreaTimer()
        canceled = true
        if (promises.cancel) {
          promises.cancel()
        }
      }
    },
    /**
     * Slightly delay showing the "cancel search" button so we don't
     * see it after every keypress, but only when a search query is lagging.
     */
    startShowSearchCancelAreaTimer() {
      this.stopShowSearchCancelAreaTimer()

      const SHOW_SEARCH_CANCEL_DELAY_MS = 5000
      this.showSearchCancelAreaTimer = window.setTimeout(() => {
        this.showSearchCancelArea = true
      }, SHOW_SEARCH_CANCEL_DELAY_MS)
    },
    stopShowSearchCancelAreaTimer() {
      this.showSearchCancelArea = false
      if (!this.showSearchCancelAreaTimer) {
        return
      }
      window.clearTimeout(this.showSearchCancelAreaTimer)
      this.showSearchCancelAreaTimer = null
    },
    cancelSearcher() {
      const { searcherCancelCallback } = this
      if (searcherCancelCallback) {
        searcherCancelCallback()
        this.searcherCancelCallback = null
      }
    },
    caseSensitiveClicked() {
      this.isCaseSensitive = !this.isCaseSensitive
      this.search()
    },
    wholeWordClicked() {
      this.isWholeWord = !this.isWholeWord
      this.search()
    },
    regexpClicked() {
      this.isRegexp = !this.isRegexp
      this.search()
    },
    openFolder() {
      this.$store.dispatch('ASK_FOR_OPEN_PROJECT')
    },
    handleFindInFolder() {
      this.keyword = this.searchMatches.value
    },
  },
  destroyed() {
    bus.off('findInFolder', this.handleFindInFolder)
  },
}
</script>

<style scoped>
  .side-bar-search {
    display: flex;
    flex-direction: column;
    height: 100%;
    padding: 26px 16px 18px;
    box-sizing: border-box;
  }
  .search-wrapper {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    margin: 0 0 12px;
    padding: 4px 6px;
    border-radius: 8px;
    border: 1px solid var(--controlBorderColor);
    background: var(--inputBgColor);
    box-sizing: border-box;
    & > input {
      color: var(--sideBarColor);
      background: transparent;
      width: 100%;
      height: 30px;
      border: none;
      outline: none;
      padding: 0 6px;
      box-sizing: border-box;
      font-size: 13px;
    }
    & > .controls {
      display: flex;
      justify-content: flex-end;
      gap: 2px;
      & > span {
        cursor: pointer;
        width: 26px;
        height: 26px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: 7px;
        transition: background-color .18s ease;
        &:hover {
          background: rgba(126, 102, 76, 0.07);
          color: var(--sideBarIconColor);
        }
        & > svg {
          fill: var(--sideBarIconColor);
          width: 15px;
          height: 15px;
          &:hover {
            fill: var(--editorColor80);
          }
        }
        &.active svg {
          fill: var(--highlightThemeColor);
        }
        &.active {
          background: var(--itemBgColor);
        }
      }
    }

    & > svg {
      cursor: pointer;
      flex-shrink: 0;
      width: 20px;
      height: 20px;
      margin-right: 10px;
      &:hover {
        color: var(--sideBarIconColor);
      }
    }
  }
  .cancel-area {
    text-align: center;
    margin: 8px 0 16px;
  }
  .search-status {
    margin: 2px 4px 10px;
    font-size: 12px;
    line-height: 1.6;
    overflow-wrap: break-word;
    color: var(--panelMutedColor);
    &.error {
      color: var(--notificationErrorBg);
    }
    & > p {
      margin: 0 0 10px;
    }
  }
  .search-result-info {
    margin-bottom: 8px;
    padding: 0 4px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--panelMutedColor);
  }
  .search-result {
    flex: 1;
    overflow-y: auto;
    overflow-x: hidden;
    padding: 0 2px 12px;
    &::-webkit-scrollbar:vertical {
      width: 8px;
    }
  }
</style>
