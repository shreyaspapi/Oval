<script lang="ts">
    import { toast, Toaster } from "svelte-sonner";
    import { onMount } from "svelte";

    import Controls from "./lib/components/Controls.svelte";
    import Installation from "./lib/components/Installation.svelte";
    import Loading from "./lib/components/Loading.svelte";

    let installed = $state(false);

    onMount(async () => {
        const pythonStatus = await window?.electronAPI?.getPythonStatus();
        if (pythonStatus) {
            const packageStatus = await window?.electronAPI?.getPackageStatus();
            if (packageStatus) {
                installed = true;
            } else {
                installed = false;
            }
        }

        window.addEventListener("message", (event) => {
            console.log("Received message from main process:", event);
            if (event.data?.type === "electron:notification") {
                if (event.data?.data?.type) {
                    toast(event.data.data.message, {
                        type: event.data?.data?.type,
                    });
                } else {
                    toast(event.data?.data.message);
                }
            }
        });
    });
</script>

<main class="w-screen h-screen bg-gray-900">
    {#if installed === null}
        <Loading />
    {:else if installed === false}
        <Installation bind:installed />
    {:else}
        <Controls />
    {/if}
</main>

<Toaster
    theme={window.matchMedia("(prefers-color-scheme: dark)").matches
        ? "dark"
        : "light"}
    richColors
    position="top-center"
/>
