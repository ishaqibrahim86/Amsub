import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'welcome_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class OnboardingPage {
  final String title;
  final String description;
  final String image;

  OnboardingPage({
    required this.title,
    required this.description,
    required this.image,
  });
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int currentIndex = 0;

  final List<OnboardingPage> pages = [
    OnboardingPage(
      title: "Automated Delivery",
      description:
      "Our range of products including affordable MTN data, GOTv, Startimes, DSTV subscriptions and electricity bills are all processed instantly.",
      image: "assets/images/onboarding1.png",
    ),
    OnboardingPage(
      title: "Airtime Solution",
      description:
      "Purchase airtime easily in Nigeria. Simply enter the amount and your airtime will be delivered instantly.",
      image: "assets/images/onboarding2.png",
    ),
    OnboardingPage(
      title: "Customer Support",
      description:
      "Experience fast support in the VTU and data reselling industry through our instant live chat assistance.",
      image: "assets/images/onboarding3.png",
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 20, top: 10),
                child: currentIndex != pages.length - 1
                    ? TextButton(
                  onPressed: completeOnboarding,
                  child: const Text(
                    "Skip",
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF6B4EFF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                    : const SizedBox(),
              ),
            ),

            // PageView
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (index) {
                  setState(() {
                    currentIndex = index;
                  });
                },
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Image fills the box like second screenshot
                        SizedBox(
                          height: 280,
                          width: double.infinity,
                          child: Image.asset(
                            page.image,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.image_not_supported,
                                size: 80,
                                color: Colors.grey,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Title
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Description
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF64748B),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Dots indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                pages.length,
                    (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: currentIndex == index ? 26 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: currentIndex == index
                        ? const Color(0xFF6B4EFF)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Next / Get Started button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: () {
                  if (currentIndex == pages.length - 1) {
                    completeOnboarding();
                  } else {
                    _controller.nextPage(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    );
                  }
                },
                child: Container(
                  height: 55,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF6B4EFF),
                        Color(0xFF8E7BFF),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.deepPurple.withOpacity(0.25),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      currentIndex == pages.length - 1
                          ? "Get Started"
                          : "Next",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const WelcomeScreen(),
      ),
    );
  }
}