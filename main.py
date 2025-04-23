import tkinter as tk
from ui import CartaoRespostaReader

class CartaoRespostaApp:
    def __init__(self):
        self.root = tk.Tk()
        self.app = CartaoRespostaReader(self.root)
    
    def run(self):
        self.root.mainloop()

if __name__ == "__main__":
    app = CartaoRespostaApp()
    app.run()