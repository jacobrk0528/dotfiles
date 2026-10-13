// Usage: osascript -l JavaScript clipboard-image.js <last-change-count> <out.png>
// Prints "<change-count> same|none|image". On "image" the clipboard's picture
// has been written to <out.png>; the caller passes the count back next time so
// each copy is only handed over once.
ObjC.import('AppKit');

function run(argv) {
	const pb = $.NSPasteboard.generalPasteboard;
	const count = String(pb.changeCount);
	if (count === argv[0]) return count + ' same';

	// A file copied in Finder carries its icon as image data; that is not a
	// picture anyone means to paste.
	if (!pb.dataForType('public.file-url').isNil()) return count + ' none';

	let png = pb.dataForType('public.png');
	if (png.isNil()) {
		// Images copied out of browsers and Preview are often TIFF only.
		const tiff = pb.dataForType('public.tiff');
		if (tiff.isNil()) return count + ' none';
		const rep = $.NSBitmapImageRep.imageRepWithData(tiff);
		if (rep.isNil()) return count + ' none';
		png = rep.representationUsingTypeProperties($.NSBitmapImageFileTypePNG, $.NSDictionary.dictionary);
	}
	png.writeToFileAtomically(argv[1], true);
	return count + ' image';
}
