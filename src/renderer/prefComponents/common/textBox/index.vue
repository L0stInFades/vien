<template>
  <section class="pref-text-box-item" :class="{'ag-underdevelop': disable}">
    <div class="description">
      <span>{{description}}:</span>
      <i class="el-icon-info" v-if="more"
        @click="handleMoreClick"
      ></i>
    </div>
    <el-input
      class="input"
      :class="{error: invalidInput}"
      :placeholder="defaultValue"
      v-model="localText"
      @input="handleInput"
      size="small"
      clearable>
    </el-input>
    <div v-if="notes" class="notes">
      {{notes}}
    </div>
  </section>
</template>

<script>
export default {
  data() {
    this.inputTimer = null
    return {
      localText: this.textValue,
      invalidInput: false,
    }
  },
  props: {
    description: String,
    notes: String,
    textValue: String,
    onChange: Function,
    more: String,
    disable: {
      type: Boolean,
      default: false,
    },
    defaultValue: {
      type: String,
      default: '',
    },
    emitTime: {
      type: Number,
      default: 800,
    },
    regexValidator: {
      type: RegExp,
      default() {
        return /(.*?)/
      },
    },
  },
  watch: {
    '$props.textValue': function (value, oldValue) {
      if (value !== oldValue) {
        this.localText = value
      }
    },
  },
  methods: {
    handleMoreClick() {
      if (typeof this.more === 'string') {
        window.api.shell.openExternal(this.more)
      }
    },
    handleInput(value) {
      const result = this.regexValidator.test(value)
      this.invalidInput = !result

      if (result) {
        // Only clear timer when input is valid, otherwise write the last value.
        if (this.inputTimer) {
          clearTimeout(this.inputTimer)
        }

        const { emitTime } = this
        if (emitTime === 0) {
          this.onChange(value)
          return
        }

        // Setting delay a little bit higher to prevent continuously file writes when typing.
        this.inputTimer = setTimeout(() => {
          this.inputTimer = null
          this.onChange(value)
        }, emitTime)
      }
    },
  },
}
</script>

<style>
  .pref-text-box-item {
    font-size: 14px;
    user-select: none;
    margin: 18px 0;
    padding: 14px 16px;
    color: var(--editorColor);
    width: 100%;
    box-sizing: border-box;
    border-radius: 18px;
    border: 1px solid var(--panelSubtleBorderColor);
    background: rgba(255, 255, 255, 0.52);
    width: 100%;
    & input.el-input__inner {
      height: 42px;
      background:
        linear-gradient(180deg, rgba(255, 255, 255, 0.84), rgba(255, 255, 255, 0.66)),
        var(--controlBgColor);
      color: var(--editorColor);
      border-color: var(--controlBorderColor);
      border-radius: 14px;
      padding-right: 15px;
      &::placeholder {
        color: var(--editorColor30);
      }
    }
    & .notes {
      margin-top: 10px;
      font-style: italic;
      font-size: 12px;
    }
    & .input {
      width: 100%;
    }
    & .el-input.is-active .el-input__inner,
    & .el-input__inner:focus {
      border-color: var(--themeColor);
      box-shadow: var(--controlFocusShadow);
    }
    & .el-input__icon,
    & .el-input__inner {
      line-height: 42px;
    }
    & .description {
      margin-bottom: 12px;
    }
    & i {
      cursor: pointer;
      opacity: .7;
      color: var(--iconColor);
    }
    & i:hover {
      color: var(--themeColor);
    }
  }
  .pref-text-box-item .el-input.error input {
    color: #f56c6c;
  }
</style>
