import SwiftUI
#if BLOCKING
import FamilyControls
#endif

struct ContentView: View {
    @EnvironmentObject var manager: FocusManager

    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.067, blue: 0.086).ignoresSafeArea()
            if manager.isActive {
                ActiveView()
            } else {
                SetupView()
            }
        }
    }
}

// MARK: - شاشة الإعداد
struct SetupView: View {
    @EnvironmentObject var manager: FocusManager
    @State private var minutes: Double = 120
    @State private var showPicker = false

    private let presets: [Int] = [25, 45, 60, 120, 180]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("وضع التركيز")
                    .font(.system(size: 32, weight: .bold))
                Text(headerText)
                    .foregroundStyle(.secondary)

                Text(format(Int(minutes)))
                    .font(.system(size: 56, weight: .light))
                    .frame(maxWidth: .infinity)

                Slider(value: $minutes, in: sliderRange, step: 5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(presets, id: \.self) { m in
                            Button(format(m)) { minutes = Double(m) }
                                .buttonStyle(.bordered)
                                .tint(Int(minutes) == m ? .blue : .gray)
                        }
                    }
                }

                #if BLOCKING
                permissionCard(
                    done: manager.authorized,
                    title: "إذن Screen Time",
                    subtitle: "مطلوب من Apple لحجب التطبيقات.",
                    action: { Task { await manager.requestAuthorization() } }
                )
                permissionCard(
                    done: manager.hasSelection,
                    title: "اختر التطبيقات المحجوبة",
                    subtitle: "اختر تطبيقات أو فئات كاملة (ألعاب، تواصل اجتماعي…).",
                    action: { showPicker = true },
                    enabled: manager.authorized
                )
                if let err = manager.authError {
                    Text(err).font(.footnote).foregroundStyle(.orange)
                }
                #else
                guidedAccessCard
                #endif

                Button {
                    manager.start(duration: minutes * 60)
                } label: {
                    Label("ابدأ التركيز", systemImage: "lock.fill")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!manager.canStart)
            }
            .padding(24)
        }
        #if BLOCKING
        .familyActivityPicker(isPresented: $showPicker, selection: $manager.selection)
        #endif
    }

    private var headerText: String {
        #if BLOCKING
        return "حدد مدة المذاكرة، وسيحجب التطبيق التطبيقات التي تشتتك."
        #else
        return "حدد مدة المذاكرة وابدأ العد التنازلي. لقفل الآيفون على التطبيق استخدم الوصول الموجَّه."
        #endif
    }

    private var sliderRange: ClosedRange<Double> {
        #if BLOCKING
        return 15...360
        #else
        return 5...360
        #endif
    }

    // دليل الوصول الموجَّه (يعمل بدون أي إذن خاص من Apple)
    private var guidedAccessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("اقفل الآيفون على التطبيق (الوصول الموجَّه)", systemImage: "hand.raised.fill")
                .font(.headline)
            Text("""
            1) مرة واحدة فقط: الإعدادات ← تسهيلات الاستخدام ← الوصول الموجَّه ← شغّله، وضع رمزًا سريًا.
            2) فعّل "اختصار تسهيلات الاستخدام" ← الوصول الموجَّه.
            3) اضغط "ابدأ التركيز"، ثم اضغط الزر الجانبي (أو زر Home) 3 مرات ← ابدأ.
            4) للخروج: اضغط الزر 3 مرات وأدخل الرمز السري.
            نصيحة: من خيارات الوصول الموجَّه اضبط "حد الوقت" على نفس مدة الجلسة.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func permissionCard(done: Bool, title: String, subtitle: String,
                                action: @escaping () -> Void, enabled: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(done ? .green : .orange)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(done ? "تعديل" : "تفعيل", action: action)
                .buttonStyle(.bordered)
                .disabled(!enabled)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func format(_ m: Int) -> String {
        let h = m / 60, r = m % 60
        if h == 0 { return "\(r) د" }
        if r == 0 { return "\(h) س" }
        return "\(h) س \(r) د"
    }
}

// MARK: - شاشة الجلسة
struct ActiveView: View {
    @EnvironmentObject var manager: FocusManager
    @State private var now = Date()
    @State private var holding = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let end = manager.endDate ?? Date()
        let remaining = max(0, end.timeIntervalSince(now))

        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
            Text("أنت في وضع التركيز").foregroundStyle(.secondary)

            Text(clock(remaining))
                .font(.system(size: 72, weight: .ultraLight).monospacedDigit())
                .environment(\.layoutDirection, .leftToRight)

            Text("ينتهي الساعة \(end.formatted(date: .omitted, time: .shortened))")
                .font(.footnote).foregroundStyle(.tertiary)

            Spacer().frame(height: 50)

            // إنهاء مبكر: اضغط مطولًا 5 ثوانٍ
            VStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(width: 200, height: 6)
                    Capsule().fill(Color.red.opacity(0.8))
                        .frame(width: holding ? 200 : 0, height: 6)
                        .animation(holding ? .linear(duration: 5) : .easeOut(duration: 0.2),
                                   value: holding)
                }
                Text("اضغط مطولًا 5 ثوانٍ للإنهاء المبكر")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(20)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 5, maximumDistance: 50,
                                perform: { manager.stop() },
                                onPressingChanged: { holding = $0 })
        }
        .onReceive(tick) { date in
            now = date
            if date >= end { manager.stop() }
        }
        .onAppear { now = Date() }
    }

    private func clock(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }
}
