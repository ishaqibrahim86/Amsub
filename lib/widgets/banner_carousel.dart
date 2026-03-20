import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/rendering.dart';

class BannerCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> banners;
  final Function(String route) onBannerTap;
  final String Function(String path) buildUrl;

  const BannerCarousel({
    super.key,
    required this.banners,
    required this.onBannerTap,
    required this.buildUrl,
  });

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {

  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _pageController = PageController(
      viewportFraction: 0.92,
    );

    _startAutoScroll();
  }

  void _startAutoScroll() {
    if (widget.banners.length <= 1) return;

    _timer?.cancel();

    _timer = Timer.periodic(
      const Duration(seconds: 5),
          (timer) {

        if (!_pageController.hasClients) return;

        int next = _currentIndex + 1;

        if (next >= widget.banners.length) {
          next = 0;
        }

        _pageController.animateToPage(
          next,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeInOut,
        );
      },
    );
  }

  void _pauseAutoScroll() {
    _timer?.cancel();
  }

  void _resumeAutoScroll() {
    _startAutoScroll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    if (widget.banners.isEmpty) {
      return const SizedBox();
    }

    return Column(
      children: [

        SizedBox(
          height: 180,
          child: NotificationListener<UserScrollNotification>(
            onNotification: (notification) {

              if (notification.direction != ScrollDirection.idle) {
                _pauseAutoScroll();
              } else {
                _resumeAutoScroll();
              }

              return true;
            },
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.banners.length,

              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },

              itemBuilder: (context, index) {

                final banner = widget.banners[index];

                final bannerPath = banner['banner'] ?? '';
                final route = banner['route'] ?? '';

                final url = widget.buildUrl(bannerPath);

                return GestureDetector(
                  onTap: () => widget.onBannerTap(route),

                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),

                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),

                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),

                      child: CachedNetworkImage(

                        imageUrl: url,
                        fit: BoxFit.cover,

                        placeholder: (context, url) => Container(
                          color: Colors.grey.shade200,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),

                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, size: 40),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            widget.banners.length,
                (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: _currentIndex == index ? 16 : 7,
              height: 7,

              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: _currentIndex == index
                    ? const Color(0xFF6B4EFF)
                    : Colors.grey.shade300,
              ),
            ),
          ),
        ),

      ],
    );
  }
}