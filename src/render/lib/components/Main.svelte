<script lang="ts">
  import { onMount } from "svelte";

  import ServerList from "./main/ServerList.svelte";
  import ServerView from "./main/ServerView.svelte";

  onMount(() => {
    console.log("Mounted");
  });
</script>

<div class="flex flex-row w-full h-full">
  <div class="">
    <ServerList />
  </div>

  <div class="my-1.5 mr-1.5 flex-1">
    <div class="w-full h-full rounded-lg border border-gray-850">
      <ServerView
        className="rounded-lg w-full h-full"
        url="http://localhost:8080"
      />
    </div>
  </div>
</div>
