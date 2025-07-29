<script lang="ts">
    import { onMount } from "svelte";

    import Spinner from "./common/Spinner.svelte";
    import logoImage from "../assets/images/splash.png";

    import galaxyImage from "../assets/images/galaxy.jpg";
    import greenImage from "../assets/images/green.jpg";
    import adamImage from "../assets/images/adam.jpg";
    import nasaImage from "../assets/images/nasa.jpg";
    import neomImage from "../assets/images/neom.jpg";
    import { fly } from "svelte/transition";

    let images = [galaxyImage, greenImage, adamImage, nasaImage, neomImage];

    let startTime = $state(null);
    let currentTime = $state(null);

    let selectedImageIdx = $state(0);

    onMount(() => {
        startTime = Date.now();
        currentTime = Date.now();

        setInterval(async () => {
            currentTime = Date.now();
        }, 1000);

        const imageInterval = setInterval(() => {
            selectedImageIdx = (selectedImageIdx + 1) % 5;
        }, 10000);
    });
</script>

<div
    class="flex flex-row w-full h-full relative text-gray-850 dark:text-gray-100 p-1"
>
    <div class="fixed right-0 my-5 mx-6 z-50">
        <div class="flex space-x-2">
            <button class=" self-center cursor-pointer outline-none">
                <img
                    src={logoImage}
                    class=" w-6 rounded-full dark:invert"
                    alt="logo"
                />
            </button>
        </div>
    </div>

    {#each images as image, index (index)}
        <div
            class="image w-full h-full absolute top-0 left-0 bg-cover bg-center transition-opacity duration-1000"
            style="opacity: {selectedImageIdx === index
                ? 1
                : 0}; background-image: url({image})"
        ></div>
    {/each}

    <div
        class="w-full h-full absolute top-0 left-0 bg-gradient-to-t from-20% from-white dark:from-black to-transparent"
    ></div>

    <div
        class="w-full h-full absolute top-0 left-0 backdrop-blur-sm bg-white dark:bg-black opacity-50"
    ></div>

    <div class=" absolute w-full top-0 left-0 right-0 z-10">
        <div class="h-6 drag-region"></div>
    </div>

    <div class="flex-1 w-full flex justify-center relative">
        <div
            class="m-auto flex flex-col justify-center text-center max-w-2xl w-full"
        >
            <div class="flex-1 w-full flex justify-center relative">
                <div class="m-auto max-w-2xl w-full">
                    <div class="flex flex-col gap-3 text-center">
                        <Spinner className="size-5" />

                        <div class=" font-secondary xl:text-lg">
                            Launching Open WebUI...
                        </div>

                        {#if currentTime - startTime > 10000}
                            <div
                                class=" font-default text-xs"
                                in:fly={{ duration: 500, y: 10 }}
                            >
                                If it's your first time, it might take a few
                                minutes to start.
                            </div>
                        {/if}
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>
