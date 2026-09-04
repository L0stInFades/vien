export const showAboutDialog = (win) => {
  if (win?.webContents) {
    win.webContents.send('mt::about-dialog')
  }
}
