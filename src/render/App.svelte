<script lang="ts">
  import { onMount } from "svelte";

  import Onboarding from "./lib/components/Onboarding.svelte";
  onMount(() => {
    console.log("Mounted");
  });
</script>

<main class="w-screen h-screen bg-gray-900">
  <Onboarding />
</main>
