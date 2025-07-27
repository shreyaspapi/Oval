<script>
    import Spinner from "./common/Spinner.svelte";
    import Versions from "./Versions.svelte";
</script>

<div class="flex-1 w-full flex justify-center relative">
    <div class="m-auto max-w-2xl w-full">
        <div class="flex flex-col gap-3 text-center">
            <Spinner className="size-5" />

            <div class=" font-secondary xl:text-lg">
                Launching Open WebUI...
            </div>

            <Versions />

            <!-- {#if $serverStartedAt}
                    {#if currentTime - $serverStartedAt > 10000}
                        <div
                            class=" font-default text-xs"
                            in:fly={{ duration: 500, y: 10 }}
                        >
                            If it's your first time, it might take a few minutes
                            to start.
                        </div>
                    {/if}
                {/if}

                <Logs show={showLogs} logs={$serverLogs} /> -->
        </div>
    </div>
</div>
