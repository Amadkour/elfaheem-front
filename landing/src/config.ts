// One place for the site origin and the Flutter app paths.
export const SITE = 'https://nextbrain.site';
export const APP = '/app';
export const LANGS = ['ar', 'en'] as const;
export type Lang = (typeof LANGS)[number];
// Same-origin API by default (nginx strips one /api, hence the doubled prefix). PUBLIC_LANDING_API_BASE is an
// optional absolute origin (https://nextbrain.site, no trailing slash) for a deploy on another host (Firebase Hosting).
export const API = `${import.meta.env.PUBLIC_LANDING_API_BASE ?? ''}/api/api/v1/public/landing`;
export const STORAGE_KEY = 'nb_lang';

/** JSON for an inline <script>: "<" escaped so a value can never close the tag. */
export const jsonForScript = (v: unknown): string => JSON.stringify(v).replace(/</g, String.fromCharCode(92) + 'u003c');
