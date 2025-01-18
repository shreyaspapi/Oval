export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export const copyToClipboard = async (text) => {
	let result = false;
	if (!navigator.clipboard) {
		const textArea = document.createElement('textarea');
		textArea.value = text;

		// Avoid scrolling to bottom
		textArea.style.top = '0';
		textArea.style.left = '0';
		textArea.style.position = 'fixed';

		document.body.appendChild(textArea);
		textArea.focus();
		textArea.select();

		try {
			const successful = document.execCommand('copy');
			const msg = successful ? 'successful' : 'unsuccessful';
			console.log('Fallback: Copying text command was ' + msg);
			result = true;
		} catch (err) {
			console.error('Fallback: Oops, unable to copy', err);
		}

		document.body.removeChild(textArea);
		return result;
	}

	result = await navigator.clipboard
		.writeText(text)
		.then(() => {
			console.log('Async: Copying to clipboard was successful!');
			return true;
		})
		.catch((error) => {
			console.error('Async: Could not copy text: ', error);
			return false;
		});

	return result;
};
