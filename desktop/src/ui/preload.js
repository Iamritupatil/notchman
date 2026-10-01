'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('notchman', {
  onState: (callback) => ipcRenderer.on('state', (_event, state) => callback(state)),
  piece: (id, index) => ipcRenderer.invoke('piece', id, index),
  control: (command) => ipcRenderer.send('control', command),
  getSettings: () => ipcRenderer.invoke('settings:get'),
  setSettings: (changes) => ipcRenderer.invoke('settings:set', changes),
  previewVoice: (voiceId) => ipcRenderer.invoke('voice:preview', voiceId),
});
