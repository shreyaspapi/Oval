<script lang="ts">
    import { onMount } from "svelte";
    import { appInfo, info } from "../stores";

    import Launching from "./Launching.svelte";
    import logoImage from "../assets/images/splash.png";
    import General from "./Controls/General.svelte";
    import About from "./Controls/About.svelte";

    let { installed = $bindable(false) } = $props();

    let selectedTab = $state("general");

    onMount(async () => {});
</script>

{#if $info?.reachable ?? false}
    <div
        class="flex flex-col w-full h-full relative text-gray-850 dark:text-gray-100"
    >
        <div
            class="pt-3 pb-1.5 {$appInfo?.platform === 'darwin'
                ? 'pl-22 pr-4'
                : 'px-4'} w-full drag-region flex flex-row gap-3 items-center justify-between"
        >
            <div class=" font-medium">Controls</div>

            <div>
                <img
                    src={logoImage}
                    class="w-6 rounded-full dark:invert"
                    alt="logo"
                />
            </div>
        </div>

        <div class=" absolute w-full top-0 left-0 right-0 z-10">
            <div class="h-6 drag-region"></div>
        </div>

        <hr class=" my-1 border-gray-850" />

        <div
            class="flex flex-col sm:flex-row w-full h-full pb-2 sm:space-x-4 px-4 pt-1"
        >
            <div
                id="admin-settings-tabs-container"
                class="tabs flex flex-row overflow-x-auto gap-2 max-w-full sm:gap-0.5 sm:flex-col sm:flex-none sm:w-26 dark:text-gray-200 text-sm font-medium text-left scrollbar-none"
            >
                <button
                    id="general"
                    class="px-0.5 py-1 min-w-fit rounded-lg sm:flex-none flex text-right transition {selectedTab ===
                    'general'
                        ? ''
                        : ' text-gray-300 dark:text-gray-600 hover:text-gray-700 dark:hover:text-white'}"
                    onclick={() => {
                        selectedTab = "general";
                    }}
                >
                    <div class=" self-center mr-2">
                        <svg
                            xmlns="http://www.w3.org/2000/svg"
                            aria-hidden="true"
                            viewBox="0 0 20 20"
                            fill="currentColor"
                            class="w-4 h-4"
                        >
                            <path
                                fill-rule="evenodd"
                                d="M8.34 1.804A1 1 0 019.32 1h1.36a1 1 0 01.98.804l.295 1.473c.497.144.971.342 1.416.587l1.25-.834a1 1 0 011.262.125l.962.962a1 1 0 01.125 1.262l-.834 1.25c.245.445.443.919.587 1.416l1.473.294a1 1 0 01.804.98v1.361a1 1 0 01-.804.98l-1.473.295a6.95 6.95 0 01-.587 1.416l.834 1.25a1 1 0 01-.125 1.262l-.962.962a1 1 0 01-1.262.125l-1.25-.834a6.953 6.953 0 01-1.416.587l-.294 1.473a1 1 0 01-.98.804H9.32a1 1 0 01-.98-.804l-.295-1.473a6.957 6.957 0 01-1.416-.587l-1.25.834a1 1 0 01-1.262-.125l-.962-.962a1 1 0 01-.125-1.262l.834-1.25a6.957 6.957 0 01-.587-1.416l-1.473-.294A1 1 0 011 10.68V9.32a1 1 0 01.804-.98l1.473-.295c.144-.497.342-.971.587-1.416l-.834-1.25a1 1 0 01.125-1.262l.962-.962A1 1 0 015.38 3.03l1.25.834a6.957 6.957 0 011.416-.587l.294-1.473zM13 10a3 3 0 11-6 0 3 3 0 016 0z"
                                clip-rule="evenodd"
                            />
                        </svg>
                    </div>
                    <div class=" self-center">{"General"}</div>
                </button>

                <button
                    id="about"
                    class="px-0.5 py-1 min-w-fit rounded-lg md:flex-none flex text-left transition {selectedTab ===
                    'about'
                        ? ''
                        : ' text-gray-300 dark:text-gray-600 hover:text-gray-700 dark:hover:text-white'}"
                    onclick={() => {
                        selectedTab = "about";
                    }}
                >
                    <div class=" self-center mr-2">
                        <svg
                            xmlns="http://www.w3.org/2000/svg"
                            aria-hidden="true"
                            viewBox="0 0 20 20"
                            fill="currentColor"
                            class="w-4 h-4"
                        >
                            <path
                                fill-rule="evenodd"
                                d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a.75.75 0 000 1.5h.253a.25.25 0 01.244.304l-.459 2.066A1.75 1.75 0 0010.747 15H11a.75.75 0 000-1.5h-.253a.25.25 0 01-.244-.304l.459-2.066A1.75 1.75 0 009.253 9H9z"
                                clip-rule="evenodd"
                            />
                        </svg>
                    </div>
                    <div class=" self-center">{"About"}</div>
                </button>
            </div>

            <div
                class="flex-1 pt-1 sm:mt-0 overflow-y-scroll pr-1 scrollbar-hidden"
            >
                {#if selectedTab === "general"}
                    <General bind:installed info={$info} />
                {:else if selectedTab === "about"}
                    <About />
                {/if}
            </div>
        </div>
    </div>
{:else}
    <Launching />
{/if}
