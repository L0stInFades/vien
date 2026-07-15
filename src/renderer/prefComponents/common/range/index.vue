<template>
  <section class="pref-range-item" :class="{'ag-underdevelop': disable}">
    <div class="description">
      <span>{{description}}:</span> <span class="value" v-if="localValue">{{localValue}} <span v-if="unit">{{unit}}</span></span>
      <i class="el-icon-info" v-if="more"
        @click="handleMoreClick"
      ></i>
    </div>
    <el-slider
      v-model="localValue"
      @change="select"
      :min="min"
      :max="max"
      :format-tooltip="value => value + (unit ? unit : '')"
      :step="step">
    </el-slider>
  </section>
</template>

<script>
export default {
  data() {
    return {
      localValue: this.currentValue,
    }
  },
  props: {
    description: String,
    currentValue: String | Number,
    min: Number,
    max: Number,
    onChange: Function,
    unit: String,
    step: Number,
    more: String,
    disable: {
      type: Boolean,
      default: false,
    },
  },
  watch: {
    '$props.currentValue': function (value, oldValue) {
      if (value !== oldValue) {
        this.localValue = value
      }
    },
  },
  methods: {
    handleMoreClick() {
      if (typeof this.more === 'string') {
        window.api.shell.openExternal(this.more)
      }
    },
    select(value) {
      this.onChange(value)
    },
  },
}
</script>

<style>
.pref-range-item {
  margin: 18px 0;
  font-size: 14px;
  color: var(--editorColor);
  width: 100%;
  padding: 14px 16px;
  box-sizing: border-box;
  border-radius: 18px;
  background: rgba(255, 255, 255, 0.52);
  border: 1px solid var(--panelSubtleBorderColor);
  & .value {
    text-align: right;
    font-size: 12px;
    font-weight: 600;
    color: var(--panelEyebrowColor);
    float: right
  }
  & .description {
    margin-bottom: 12px;
  }
  & .el-slider {
    width: 100%;
  }
  & .el-slider__runway,
  & .el-slider__bar {
    height: 6px;
    border-radius: 999px;
  }
  & .el-slider__runway {
    background: rgba(126, 102, 76, 0.1);
  }
  & .el-slider__button {
    width: 14px;
    height: 14px;
    background: #fff;
    box-shadow: 0 4px 10px rgba(118, 94, 68, 0.12);
  }
  & .el-slider__button-wrapper {
    width: 24px;
    height: 24px;
    top: -10px;
  }
}
.pref-select-item .description {
  margin-bottom: 10px;

  & .value {
    color: var(--editorColor80);
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
</style>
