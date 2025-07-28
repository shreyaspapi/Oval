<script>
    import { onMount } from "svelte";
    import Versions from "../Versions.svelte";
    import Spinner from "../common/Spinner.svelte";

    let version = $state(null);

    onMount(async () => {
        // Fetch the version from the main process
        version = await window.electronAPI.getVersion();
    });
</script>

{#if version}
    <div
        id="tab-about"
        class="flex flex-col h-full justify-between space-y-3 text-sm mb-6"
    >
        <div class=" space-y-3 overflow-y-scroll max-h-[28rem] lg:max-h-full">
            <div>
                <div
                    class=" mb-1 text-sm font-medium flex space-x-2 items-center"
                >
                    <div>Open WebUI Desktop Version</div>
                </div>

                <div class="flex w-full justify-between items-center">
                    <div
                        class="flex flex-col text-xs text-gray-700 dark:text-gray-200"
                    >
                        <div class="flex gap-1">
                            v{version}
                        </div>

                        <button
                            class=" underline flex items-center space-x-1 text-xs text-gray-500 dark:text-gray-500 cursor-pointer"
                            onclick={() => {
                                window.electronAPI.openInBrowser(
                                    "https://desktop.openwebui.com"
                                );
                            }}
                        >
                            <div>{"See what's new"}</div>
                        </button>
                    </div>
                </div>
            </div>

            <hr class=" border-gray-100 dark:border-gray-850" />

            <div class="flex space-x-1">
                <a href="https://discord.gg/5rJgQTnV4s" target="_blank">
                    <img
                        alt="Discord"
                        src="https://img.shields.io/badge/Discord-Open_WebUI-blue?logo=discord&logoColor=white"
                    />
                </a>

                <a href="https://twitter.com/OpenWebUI" target="_blank">
                    <img
                        alt="X (formerly Twitter) Follow"
                        src="https://img.shields.io/twitter/follow/OpenWebUI"
                    />
                </a>

                <a
                    href="https://github.com/open-webui/open-webui"
                    target="_blank"
                >
                    <img
                        alt="Github Repo"
                        src="https://img.shields.io/github/stars/open-webui/open-webui?style=social&label=Star us on Github"
                    />
                </a>
            </div>

            <div class="mt-1 text-xs text-gray-400 dark:text-gray-500">
                Emoji graphics provided by
                <a href="https://github.com/jdecked/twemoji" target="_blank"
                    >Twemoji</a
                >, licensed under
                <a
                    href="https://creativecommons.org/licenses/by/4.0/"
                    target="_blank">CC-BY 4.0</a
                >.
            </div>

            <div>
                <div class="text-xs text-gray-400 dark:text-gray-500">
                    Copyright (c) {new Date().getFullYear()}
                    <a
                        href="https://openwebui.com"
                        target="_blank"
                        class="underline">Open WebUI (Timothy Jaeryang Baek)</a
                    >
                    All rights reserved.
                </div>
            </div>

            <div class="text-xs text-transparent">
                <Versions />
            </div>
        </div>
    </div>
{:else}
    <div
        class="flex flex-row w-full h-full relative text-gray-850 dark:text-gray-100 drag-region"
    >
        <div class="flex-1 w-full flex justify-center relative">
            <div class="m-auto">
                <Spinner />
            </div>
        </div>
    </div>
{/if}
