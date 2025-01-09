<script lang="ts">
  let { className, url } = $props();
</script>

<!-- iframe -->
<iframe class={className} src={url} frameborder="0"></iframe>
