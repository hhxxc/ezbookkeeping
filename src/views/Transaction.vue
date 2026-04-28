<template>
  <!-- ... existing code ... -->
  <el-dropdown @command="handleAmountFilter">
    <span class="el-dropdown-link">
      金额<i class="el-icon-arrow-down el-icon--right"></i>
    </span>
    <el-dropdown-menu slot="dropdown">
      <el-dropdown-item command="asc">正序</el-dropdown-item>
      <el-dropdown-item command="desc">倒叙</el-dropdown-item>
    </el-dropdown-menu>
  </el-dropdown>
  <!-- ... existing code ... -->
</template>

<script>
export default {
  methods: {
    handleAmountFilter(command) {
      this.transactionListReq.sortBy = 'amount';
      this.transactionListReq.sortOrder = command;
      this.fetchTransactions();
    },
    fetchTransactions() {
    }
  }
}
</script>