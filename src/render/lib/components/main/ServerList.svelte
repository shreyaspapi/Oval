<script lang="ts">
  import Plus from "../icons/Plus.svelte";
  import FaviconImage from "../../assets/images/favicon.png";
</script>

<div
  class="flex flex-col gap-2.5 w-16 h-full py-3.5 px-2.5 max-h-screen overflow-y-auto bg-gray-900"
>
  <div class=" w-full flex justify-center">
    <button
      class="size-11 flex justify-center self-center bg-gray-800 text-gray-100 rounded-full cursor-pointer"
      onclick={() => {
        console.log("Clicked");
      }}
    >
      <img src={FaviconImage} class="w-full h-full" />
    </button>
  </div>

  <div class=" w-full flex justify-center">
    <button
      class="size-11 flex justify-center self-center bg-gray-800 text-gray-100 rounded-full cursor-pointer"
      onclick={() => {
        console.log("Clicked");
      }}
    >
      <div class="m-auto">
        <Plus className=" size-5" strokeWidth="2.5" />
      </div>
    </button>
  </div>
</div>
