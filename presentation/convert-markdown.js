#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

// Read the markdown file
const markdownPath = path.join(__dirname, '..', 'aws-community-builders-presentation.md');
const markdownContent = fs.readFileSync(markdownPath, 'utf8');

// Split markdown into sections based on ## headers
const sections = markdownContent.split(/^## /gm).filter(section => section.trim());

// Convert markdown sections to HTML slides
function convertToSlides(sections) {
    let slidesHtml = '';
    
    sections.forEach((section, index) => {
        if (index === 0) return; // Skip the title section as it's handled separately
        
        const lines = section.split('\n');
        const title = lines[0];
        const content = lines.slice(1).join('\n');
        
        // Create section wrapper for multi-slide sections
        if (title.includes('Deep Dive') || title.includes('Integration') || title.includes('Analysis')) {
            slidesHtml += `
            <section>
                <section>
                    <h2>${title}</h2>
                </section>
                ${convertContentToSlides(content)}
            </section>`;
        } else {
            slidesHtml += `
            <section>
                <h2>${title}</h2>
                ${convertContent(content)}
            </section>`;
        }
    });
    
    return slidesHtml;
}

function convertContent(content) {
    // Convert markdown to HTML (basic conversion)
    return content
        .replace(/### (.*)/g, '<h3>$1</h3>')
        .replace(/#### (.*)/g, '<h4>$1</h4>')
        .replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>')
        .replace(/\*(.*?)\*/g, '<em>$1</em>')
        .replace(/```([^`]+)```/g, '<pre><code>$1</code></pre>')
        .replace(/`([^`]+)`/g, '<code>$1</code>')
        .replace(/^- (.*)/gm, '<li>$1</li>')
        .replace(/(<li>.*<\/li>)/s, '<ul>$1</ul>')
        .replace(/^\d+\. (.*)/gm, '<li>$1</li>')
        .replace(/(<li>.*<\/li>)/s, '<ol>$1</ol>');
}

function convertContentToSlides(content) {
    // Split content by ### headers for sub-slides
    const subSections = content.split(/^### /gm).filter(s => s.trim());
    let subSlidesHtml = '';
    
    subSections.forEach(subSection => {
        const lines = subSection.split('\n');
        const subTitle = lines[0];
        const subContent = lines.slice(1).join('\n');
        
        subSlidesHtml += `
        <section>
            <h3>${subTitle}</h3>
            ${convertContent(subContent)}
        </section>`;
    });
    
    return subSlidesHtml;
}

console.log('Markdown to Reveal.js converter ready!');
console.log('The HTML presentation is already created in index.html');
console.log('Run "npm start" to view the presentation');