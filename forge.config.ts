import type { ForgeConfig } from '@electron-forge/shared-types';
import { MakerSquirrel } from '@electron-forge/maker-squirrel';
import { MakerDMG } from '@electron-forge/maker-dmg';
import { MakerZIP } from '@electron-forge/maker-zip';
import { MakerDeb } from '@electron-forge/maker-deb';
import { MakerRpm } from '@electron-forge/maker-rpm';
import { VitePlugin } from '@electron-forge/plugin-vite';
import { FusesPlugin } from '@electron-forge/plugin-fuses';
import { FuseV1Options, FuseVersion } from '@electron/fuses';

import os from 'os';

const config: ForgeConfig = {
	packagerConfig: {
		executableName: 'open-webui',
		asar: true,
		icon: 'public/assets/icon.png',
		extraResource: ['public/assets', 'resources'],
		osxSign: {
			optionsForFile: (filePath) => {
				return {
					entitlements: 'entitlements.plist'
				};
			}
		}
		// osxNotarize: {
		// 	appleId: process.env.APPLE_ID,
		// 	appleIdPassword: process.env.APPLE_PASSWORD,
		// 	teamId: process.env.APPLE_TEAM_ID
		// }
	},
	rebuildConfig: {},
	makers: [
		new MakerSquirrel({}),
		// new MakerZIP({}, ['darwin']),
		new MakerDMG(
			// @ts-expect-error Incorrect TS typings (https://github.com/electron/forge/issues/3712)
			{
				icon: 'public/assets/icon.icns',
				background: 'public/assets/dmg-background.png',
				format: 'ULFO',
				contents: [
					{
						x: 225,
						y: 250,
						type: 'file',
						path: `${process.cwd()}/out/Open WebUI-darwin-${os.arch()}/Open WebUI.app`
					},
					{
						x: 400,
						y: 240,
						type: 'link',
						path: '/Applications'
					}
				]
			}
		),
		new MakerRpm({}),
		new MakerDeb({})
	],
	plugins: [
		new VitePlugin({
			// `build` can specify multiple entry builds, which can be Main process, Preload scripts, Worker process, etc.
			// If you are familiar with Vite configuration, it will look really familiar.
			build: [
				{
					// `entry` is just an alias for `build.lib.entry` in the corresponding file of `config`.
					entry: 'src/main.ts',
					config: 'vite.main.config.ts',
					target: 'main'
				},
				{
					entry: 'src/preload.ts',
					config: 'vite.preload.config.ts',
					target: 'preload'
				}
			],
			renderer: [
				{
					name: 'main_window',
					config: 'vite.renderer.config.mts'
				}
			]
		}),
		// Fuses are used to enable/disable various Electron functionality
		// at package time, before code signing the application
		new FusesPlugin({
			version: FuseVersion.V1,
			[FuseV1Options.RunAsNode]: false,
			[FuseV1Options.EnableCookieEncryption]: true,
			[FuseV1Options.EnableNodeOptionsEnvironmentVariable]: false,
			[FuseV1Options.EnableNodeCliInspectArguments]: false,
			[FuseV1Options.EnableEmbeddedAsarIntegrityValidation]: true,
			[FuseV1Options.OnlyLoadAppFromAsar]: true
		})
	]
};

export default config;
