<template>
  <section class="pref-switch-item" :class="{'ag-underdevelop': disable}">
    <div class="description">
      <span>{{description}}:</span>
      <i class="el-icon-info" v-if="more"
        @click="handleMoreClick"
      ></i>
      <el-tooltip
        v-else-if="detailedDescription"
        :content="detailedDescription"
        class="item"
        effect="dark"
        placement="top-start"
      >
        <i class="el-icon-info"></i>
      </el-tooltip>
      <span v-if="notes" class="notes">
        {{notes}}
      </span>
    </div>
    <el-switch
      v-model="status"
      @change="handleSwitchChange">
    </el-switch>
  </section>
</template>

<script>
export default {
  data() {
    return {
      status: this.isOn,
    }
  },
  props: {
    description: String,
    notes: String,
    isOn: Boolean,
    onChange: Function,
    more: String,
    detailedDescription: String,
    disable: {
      type: Boolean,
      default: false,
    },
  },
  watch: {
    '$props.isOn': function (value, oldValue) {
      if (value !== oldValue) {
        this.status = value
      }
    },
  },
  methods: {
    handleMoreClick() {
      if (typeof this.more === 'string') {
        window.api.shell.openExternal(this.more)
      }
    },
    handleSwitchChange(value) {
      this.onChange(value)
    },
  },
}
</script>

<style>
  .pref-switch-item {
    font-size: 14px;
    user-select: none;
    margin: 18px 0;
    padding: 14px 16px;
    color: var(--editorColor);
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    border-radius: 18px;
    border: 1px solid var(--panelSubtleBorderColor);
    background: rgba(255, 255, 255, 0.52);

    & .description {
      flex: 1;
      line-height: 1.5;
      & i {
        cursor: pointer;
        opacity: .7;
        color: var(--iconColor);
      }
      & i:hover {
        color: var(--themeColor);
      }
    }

    & .notes {
      font-style: italic;
      font-size: 12px;
    }
  }

  span.el-switch__core::after {
    top: 2px;
    left: 4px;
    width: 14px;
    height: 14px;
  }

  .el-switch .el-switch__core {
    width: 42px !important;
    height: 20px;
    border: 1px solid var(--controlBorderColor);
    background: rgba(126, 102, 76, 0.08);
    box-sizing: border-box;
    border-radius: 999px;
  }

  span.el-switch__label {
    color: var(--editorColor50);
  }

  .el-switch:not(.is-checked) .el-switch__core::after {
    background: rgba(126, 102, 76, 0.56);
  }
</style>
