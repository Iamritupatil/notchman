'use strict';

module.exports = {
  // The Notchman server on AWS (same as the iPhone app). Can be overridden for testing.
  apiURL: process.env.NOTCHMAN_API_URL || 'https://x6clb2pbdxbr55i5sdradcnqw40bmqrt.lambda-url.us-east-1.on.aws/',

  voices: [
    { id: '21m00Tcm4TlvDq8ikWAM', name: 'Rachel', detail: 'Calm, clear · American' },
    { id: 'EXAVITQu4vr4xnSDxMaL', name: 'Sarah', detail: 'Soft, confident · American' },
    { id: '9BWtsMINqrJLrRacOk9x', name: 'Aria', detail: 'Expressive · American' },
    { id: 'XB0fDUnXU5powFXDhCwa', name: 'Charlotte', detail: 'Warm · Swedish-English' },
    { id: 'pFZP5JQG7iQjIQuC4Bku', name: 'Lily', detail: 'Gentle · British' },
    { id: 'JBFqnCBsd6RMkjVDRZzb', name: 'George', detail: 'Warm narrator · British' },
    { id: 'onwK4e9ZLuTAKqWW03F9', name: 'Daniel', detail: 'Steady, news-style · British' },
    { id: 'nPczCjzI2devNBz1zQrb', name: 'Brian', detail: 'Deep, relaxed · American' },
    { id: 'pNInz6obpgDQGcFmaJgB', name: 'Adam', detail: 'Deep, clear · American' },
  ],

  defaults: {
    voiceId: '21m00Tcm4TlvDq8ikWAM',
    speed: 1,
    tldrShortcut: 'Alt+T',
    readShortcut: 'Alt+R',
    openAtLogin: true,
  },

  // Offered in Settings if the default is taken by another app.
  shortcutChoices: {
    tldr: ['Alt+T', 'CommandOrControl+Alt+T', 'CommandOrControl+Shift+T', 'Alt+Space'],
    read: ['Alt+R', 'CommandOrControl+Alt+R', 'CommandOrControl+Shift+R'],
  },
};
