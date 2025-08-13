# Web-Based Presentation Setup

This directory contains multiple options for converting your markdown presentation into a beautiful web-based slideshow.

## Option 1: Reveal.js (Recommended) 🚀

**Best for:** Professional presentations with advanced features, animations, and customization.

### Quick Start:
```bash
cd presentation
npm install
npm start
```

This will:
- Install dependencies
- Start a local server at http://localhost:8080
- Open your presentation in the browser

### Features:
- ✅ Professional AWS/Snowflake themed design
- ✅ Smooth transitions and animations
- ✅ Speaker notes support
- ✅ PDF export capability
- ✅ Mobile responsive
- ✅ Keyboard navigation
- ✅ Progress bar

### Controls:
- **Arrow keys** or **Space**: Navigate slides
- **ESC**: Overview mode
- **S**: Speaker notes
- **F**: Fullscreen
- **B**: Blackout screen

---

## Option 2: Marp (Markdown Presentation) 📝

**Best for:** Quick setup, markdown-native approach.

### Quick Start:
```bash
# Install Marp CLI globally
npm install -g @marp-team/marp-cli

# Generate HTML presentation
marp marp-presentation.md --html --output presentation.html

# Or start live server
marp marp-presentation.md --server --html
```

### Features:
- ✅ Pure markdown syntax
- ✅ Live reload during editing
- ✅ PDF/PowerPoint export
- ✅ Custom themes
- ✅ Simple setup

---

## Option 3: GitPitch Style (Alternative)

If you prefer a different approach, you can also use:

### Slidev
```bash
npm install -g @slidev/cli
slidev marp-presentation.md
```

### Remark.js
Simple HTML file with markdown content loaded dynamically.

---

## Customization

### Colors & Branding
The presentations use:
- **AWS Orange**: #FF9900
- **AWS Blue**: #232F3E  
- **Snowflake Blue**: #29B5E8

### Adding Images
Place images in the `presentation/assets/` directory and reference them:
```markdown
![Architecture](assets/architecture-diagram.png)
```

### Custom CSS
Edit the `<style>` section in `index.html` for Reveal.js or modify the Marp theme.

---

## Presenting Tips

### Before Your Presentation:
1. **Test on presentation hardware** - Run `npm start` and test on the actual projector/screen
2. **Have a backup** - Export to PDF using browser print function
3. **Check internet** - All resources are CDN-based, ensure stable connection
4. **Practice navigation** - Familiarize yourself with keyboard shortcuts

### During Presentation:
- Use **arrow keys** for navigation
- Press **B** to blackout screen during discussions
- Use **ESC** for slide overview
- **F** for fullscreen mode

### For Remote Presentations:
- Share your entire screen, not just the browser window
- Test screen sharing beforehand
- Have the demo environment ready in separate tabs

---

## Export Options

### PDF Export (Reveal.js):
1. Add `?print-pdf` to the URL
2. Use browser print function
3. Save as PDF

### PowerPoint Export (Marp):
```bash
marp marp-presentation.md --pptx --output presentation.pptx
```

---

## Troubleshooting

### Common Issues:

**Slides not loading:**
- Check if you're running the server (`npm start`)
- Verify all files are in the correct directory

**Styling issues:**
- Clear browser cache
- Check console for CSS/JS errors

**Performance issues:**
- Close other browser tabs
- Use Chrome/Firefox for best performance

**Demo not working:**
- Ensure demo environment is set up per main README
- Have backup screenshots ready

---

## File Structure

```
presentation/
├── index.html              # Reveal.js presentation
├── marp-presentation.md    # Marp markdown version
├── package.json           # Dependencies
├── convert-markdown.js    # Conversion utilities
├── assets/               # Images and media
└── README.md            # This file
```

---

## Next Steps

1. **Choose your preferred option** (Reveal.js recommended)
2. **Customize colors/branding** to match your style
3. **Add your contact information** in the final slide
4. **Test the demo environment** using the main demo setup
5. **Practice the presentation** with the web interface

Happy presenting! 🎉