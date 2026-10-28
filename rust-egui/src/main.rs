use eframe::egui;

fn main() -> eframe::Result<()> {
    let options = eframe::NativeOptions::default();
    eframe::run_native(
        "Hello world",
        options,
        Box::new(|_cc| Ok(Box::new(HelloApp))),
    )
}

struct HelloApp;

impl eframe::App for HelloApp {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ui, |ui| {
            ui.heading("Hello world");
        });
    }
}
