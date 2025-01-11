<script lang="ts">
  import { onMount } from "svelte";
</script>

<div class="flex flex-row w-full h-full relative">
  <div
    class="absolute top-0 left-0 w-full h-6 bg-gray-900 bg-opacity-50 draggable"
  ></div>
  <div class="m-auto flex flex-col">
    <div class=" flex justify-center mb-3">
      <img
        src="./assets/images/splash.png"
        class="size-16 dark:invert"
        alt="hero"
      />
    </div>

    <!-- <div class=" text-2xl text-gray-50 font-secondary">Install Open WebUI</div> -->

    <button
      class=" text-gray-100 hover:text-white transition font-medium cursor-pointer"
      onclick={() => {
        console.log("install clicked");
        if (window?.electronAPI) {
          window.electronAPI.installPackage();
        }
      }}>Install Open WebUI</button
    >

    <button
      class=" text-gray-100 hover:text-white transition font-medium cursor-pointer"
      onclick={() => {
        console.log("start clicked");
        if (window?.electronAPI) {
          window.electronAPI.startServer();
        }
      }}>Start Open WebUI</button
    >

    <button
      class=" text-gray-100 hover:text-white transition font-medium cursor-pointer"
      onclick={() => {
        console.log("stop clicked");
        if (window?.electronAPI) {
          window.electronAPI.stopServer();
        }
      }}>Stop Open WebUI</button
    >
  </div>
</div>

<style>
  .draggable {
    -webkit-app-region: drag;
  }
</style>
