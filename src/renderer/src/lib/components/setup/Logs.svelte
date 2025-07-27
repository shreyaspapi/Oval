<script lang="ts">
	import { toast } from 'svelte-sonner';
	import Tooltip from '../common/Tooltip.svelte';
	import { copyToClipboard } from '../../utils';

	export let show;
	export let logs = [];
</script>

{#if show}
	<div class="relative max-w-full w-full px-3">
		{#if logs.length > 0}
			<div class="absolute top-0 right-0 p-1 bg-transparent text-xs font-mono">
				<Tooltip content="Copy">
					<button
						class="text-xs cursor-pointer"
						type="button"
						on:click={async () => {
							await copyToClipboard(logs.join('\n'));

							toast.success('Logs copied to clipboard');
						}}
					>
						<svg
							xmlns="http://www.w3.org/2000/svg"
							fill="none"
							viewBox="0 0 24 24"
							stroke-width="2.3"
							stroke="currentColor"
							class="w-4 h-4"
						>
							<path
								stroke-linecap="round"
								stroke-linejoin="round"
								d="M15.666 3.888A2.25 2.25 0 0013.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 01-.75.75H9a.75.75 0 01-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 01-2.25 2.25H6.75A2.25 2.25 0 014.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 011.927-.184"
							/>
						</svg>
					</button>
				</Tooltip>
			</div>
		{/if}

		<div
			class="text-xs font-mono text-left max-h-40 overflow-auto max-w-full w-full flex flex-col-reverse scrollbar-hidden no-drag-region"
		>
			{#each logs.reverse() as log, idx}
				<div class="text-xs font-mono whitespace-pre-wrap text-wrap max-w-full w-full">
					{log}
				</div>
			{/each}
		</div>
	</div>
{/if}
