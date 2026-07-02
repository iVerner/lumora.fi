import PhotoSwipeLightbox from '/vendor/photoswipe/photoswipe-lightbox.esm.js';

const gallery = document.querySelector('#album-gallery');

if (gallery) {
	const items = Array.from(gallery.querySelectorAll('.album-flow__item'));
	const setActiveItem = (index) => {
		items.forEach((item, itemIndex) => {
			item.classList.toggle('is-active', itemIndex === index);
		});
	};

	const lightbox = new PhotoSwipeLightbox({
		gallery: '#album-gallery',
		children: 'a',
		bgOpacity: 0.92,
		wheelToZoom: true,
		pswpModule: () => import('/vendor/photoswipe/photoswipe.esm.js')
	});

	lightbox.on('change', () => {
		if (lightbox.pswp) {
			setActiveItem(lightbox.pswp.currIndex);
		}
	});

	items.forEach((item, index) => {
		item.addEventListener('click', () => setActiveItem(index));
	});

	lightbox.init();
}
