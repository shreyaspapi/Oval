import { mount } from 'svelte';
import './render/app.css';
import 'tippy.js/dist/tippy.css';

import App from './render/App.svelte';

const app = mount(App, {
	target: document.getElementById('app')
});

export default app;
