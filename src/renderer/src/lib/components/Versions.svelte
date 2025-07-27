<script lang="ts">
    const versions = window.electron.process.versions;
    import { Accordion } from "bits-ui";
</script>

<ul class="versions">
    <li class="electron-version">Electron v{versions.electron}</li>
    <li class="chrome-version">Chromium v{versions.chrome}</li>
    <li class="node-version">Node v{versions.node}</li>
</ul>

<Accordion.Root class="mx-auto w-full max-w-md">
    <Accordion.Item class="mb-2 rounded-md border border-gray-200">
        <Accordion.Header
            class="bg-gray-50 transition-colors hover:bg-gray-100"
        >
            <Accordion.Trigger
                class="flex w-full items-center justify-between p-4 text-left font-medium"
            >
                <span>Tailwind-styled Accordion</span>
                <svg
                    class="h-5 w-5 transform transition-transform"
                    xmlns="http://www.w3.org/2000/svg"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke="currentColor"
                >
                    <path
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        stroke-width="2"
                        d="M19 9l-7 7-7-7"
                    />
                </svg>
            </Accordion.Trigger>
        </Accordion.Header>
        <Accordion.Content class="p-4 text-gray-700">
            This accordion is styled using Tailwind CSS classes.
        </Accordion.Content>
    </Accordion.Item>
</Accordion.Root>
