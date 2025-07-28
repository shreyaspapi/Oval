<script lang="ts">
    import { Switch } from "bits-ui";

    let { state = $bindable(), id, onChange } = $props();
</script>

<Switch.Root
    bind:checked={state}
    {id}
    onCheckedChange={onChange}
    class="flex h-5 min-h-5 w-9 shrink-0 cursor-pointer items-center rounded-full px-[3px] mx-[1px] transition outline outline-1 outline-gray-100 dark:outline-gray-800 {state
        ? ' bg-emerald-600'
        : 'bg-gray-200 dark:bg-transparent'}"
>
    <Switch.Thumb
        class="pointer-events-none block size-4 shrink-0 rounded-full bg-white transition-transform data-[state=checked]:translate-x-3.5 data-[state=unchecked]:translate-x-0 data-[state=unchecked]:shadow-mini "
    />
</Switch.Root>
