// One place for the site origin and the Flutter app paths.
export const SITE = 'https://nextbrain.site';
export const APP = '/app';
export const LANGS = ['ar', 'en'] as const;
export type Lang = (typeof LANGS)[number];
// Same-origin API (nginx strips one /api, hence the doubled prefix).
export const API = '/api/api/v1/public/landing';
export const STORAGE_KEY = 'nb_lang';

/** JSON for an inline <script>: "<" escaped so a value can never close the tag. */
export const jsonForScript = (v: unknown): string => JSON.stringify(v).replace(/</g, String.fromCharCode(92) + 'u003c');
