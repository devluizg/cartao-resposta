import tkinter as tk
from tkinter import ttk, filedialog, messagebox
from PIL import Image, ImageTk
import cv2
import os
import numpy as np
from analysis import CartaoRespostaAnalyzer, MultiColumnCartaoAnalyzer, detectar_colunas

class CartaoRespostaReader:
    def __init__(self, root):
        self.root = root
        self.root.title("Leitor de Cartão Resposta")
        self.root.geometry("1200x700")
        self.root.configure(bg="#f0f0f0")
        
        self.image_path = None
        self.processed_image = None
        self.debug_image = None
        self.resultados = {}
        self.alternativas = ['A', 'B', 'C', 'D', 'E']
        self.analyzer = CartaoRespostaAnalyzer()
        self.multi_analyzer = MultiColumnCartaoAnalyzer(self.analyzer)
        
        self.setup_ui()
    
    def setup_ui(self):
        main_frame = ttk.Frame(self.root)
        main_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
        
        left_frame = ttk.Frame(main_frame)
        left_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        right_frame = ttk.Frame(main_frame)
        right_frame.pack(side=tk.RIGHT, fill=tk.BOTH, padx=(10, 0))
        
        self.image_frame = ttk.LabelFrame(left_frame, text="Imagem do Cartão")
        self.image_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 10))
        
        self.image_label = ttk.Label(self.image_frame)
        self.image_label.pack(fill=tk.BOTH, expand=True, padx=5, pady=5)
        
        config_frame = ttk.LabelFrame(left_frame, text="Configurações")
        config_frame.pack(fill=tk.X, pady=(0, 10))
        
        ttk.Label(config_frame, text="Número de questões:").grid(row=0, column=0, padx=5, pady=5, sticky=tk.W)
        self.num_questoes_var = tk.StringVar(value="10")
        self.num_questoes_entry = ttk.Entry(config_frame, textvariable=self.num_questoes_var, width=5)
        self.num_questoes_entry.grid(row=0, column=1, padx=5, pady=5, sticky=tk.W)
        
        ttk.Label(config_frame, text="Colunas:").grid(row=0, column=2, padx=5, pady=5, sticky=tk.W)
        self.num_colunas_var = tk.StringVar(value="1")
        self.num_colunas_combo = ttk.Combobox(config_frame, textvariable=self.num_colunas_var, 
                                               values=["1", "2", "3"], width=5, state="readonly")
        self.num_colunas_combo.grid(row=0, column=3, padx=5, pady=5, sticky=tk.W)
        
        ttk.Label(config_frame, text="Limiar (threshold):").grid(row=1, column=0, padx=5, pady=5, sticky=tk.W)
        self.threshold_var = tk.StringVar(value="150")
        threshold_entry = ttk.Entry(config_frame, textvariable=self.threshold_var, width=5)
        threshold_entry.grid(row=1, column=1, padx=5, pady=5, sticky=tk.W)
        
        ttk.Label(config_frame, text="Sensibilidade (%):").grid(row=1, column=2, padx=5, pady=5, sticky=tk.W)
        self.sensitivity_var = tk.StringVar(value="30")
        sensitivity_entry = ttk.Entry(config_frame, textvariable=self.sensitivity_var, width=5)
        sensitivity_entry.grid(row=1, column=3, padx=5, pady=5, sticky=tk.W)
        
        self.auto_detect_var = tk.BooleanVar(value=False)
        self.auto_detect_check = ttk.Checkbutton(config_frame, text="Detectar colunas automaticamente", 
                                                 variable=self.auto_detect_var)
        self.auto_detect_check.grid(row=2, column=0, columnspan=4, padx=5, pady=5, sticky=tk.W)
        
        button_frame = ttk.Frame(left_frame)
        button_frame.pack(fill=tk.X)
        
        self.load_button = ttk.Button(button_frame, text="Carregar Imagem", command=self.load_image)
        self.load_button.pack(side=tk.LEFT, padx=5)
        
        self.process_button = ttk.Button(button_frame, text="Processar Imagem", command=self.process_image)
        self.process_button.pack(side=tk.LEFT, padx=5)
        self.process_button["state"] = "disabled"
        
        self.view_processed_button = ttk.Button(button_frame, text="Ver Processamento", command=self.view_processed)
        self.view_processed_button.pack(side=tk.LEFT, padx=5)
        self.view_processed_button["state"] = "disabled"
        
        self.save_button = ttk.Button(button_frame, text="Salvar Resultados", command=self.save_results)
        self.save_button.pack(side=tk.LEFT, padx=5)
        self.save_button["state"] = "disabled"
        
        result_frame = ttk.LabelFrame(right_frame, text="Respostas Detectadas")
        result_frame.pack(fill=tk.BOTH, expand=True)
        
        self.result_text = tk.Text(result_frame, width=20, height=30, font=("Courier", 12))
        self.result_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=5, pady=5)
        
        scrollbar = ttk.Scrollbar(result_frame, command=self.result_text.yview)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.result_text.config(yscrollcommand=scrollbar.set)
        
        self.status_var = tk.StringVar()
        self.status_var.set("Pronto")
        status_bar = ttk.Label(self.root, textvariable=self.status_var, relief=tk.SUNKEN, anchor=tk.W)
        status_bar.pack(side=tk.BOTTOM, fill=tk.X)
    
    def load_image(self):
        self.image_path = filedialog.askopenfilename(
            title="Selecione a imagem do cartão resposta",
            filetypes=[("Imagens", "*.png *.jpg *.jpeg *.bmp")]
        )
        
        if self.image_path:
            try:
                image = cv2.imread(self.image_path)
                image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
                self.display_image(image)
                
                if self.auto_detect_var.get():
                    gray = cv2.cvtColor(image, cv2.COLOR_RGB2GRAY)
                    _, binary = cv2.threshold(gray, int(self.threshold_var.get()), 255, cv2.THRESH_BINARY_INV)
                    num_colunas = detectar_colunas(binary)
                    self.num_colunas_var.set(str(num_colunas))
                    self.status_var.set(f"Imagem carregada. Detectadas {num_colunas} colunas.")
                else:
                    self.status_var.set(f"Imagem carregada: {os.path.basename(self.image_path)}")
                
                self.process_button["state"] = "normal"
            except Exception as e:
                messagebox.showerror("Erro", f"Erro ao carregar a imagem: {str(e)}")
                self.status_var.set("Erro ao carregar a imagem")
    
    def display_image(self, cv_image, window=None):
        h, w = cv_image.shape[:2]
        max_h, max_w = 600, 800

        if h > max_h or w > max_w:
            scale = min(max_h / h, max_w / w)
            new_h, new_w = int(h * scale), int(w * scale)
            cv_image = cv2.resize(cv_image, (new_w, new_h))

        pil_image = Image.fromarray(cv_image)
        photo = ImageTk.PhotoImage(pil_image)

        if window is None:
            self.image_label.config(image=photo)
            self.image_label.image = photo
        else:
            # Remover ou comentar esta linha:
            # window.title("Imagem Processada")  ← Erro aqui
            label = ttk.Label(window)
            label.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
            label.config(image=photo)
            label.image = photo

    
    def process_image(self):
        if not self.image_path:
            messagebox.showwarning("Aviso", "Carregue uma imagem primeiro.")
            return
        
        try:
            num_questoes = int(self.num_questoes_var.get())
            num_colunas = int(self.num_colunas_var.get())
            threshold_value = int(self.threshold_var.get())
            sensitivity = int(self.sensitivity_var.get()) / 100.0
            
            image = cv2.imread(self.image_path)
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            blurred = cv2.GaussianBlur(gray, (5, 5), 0)
            _, binary = cv2.threshold(blurred, threshold_value, 255, cv2.THRESH_BINARY_INV)
            
            kernel = np.ones((3, 3), np.uint8)
            binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)
            
            self.processed_image = binary.copy()
            debug_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            
            if self.auto_detect_var.get():
                detected_cols = detectar_colunas(binary)
                self.num_colunas_var.set(str(detected_cols))
                num_colunas = detected_cols
                self.status_var.set(f"Detectadas {num_colunas} colunas automaticamente")
            else:
                # Usa exatamente o que o usuário informou
                self.status_var.set(f"Usando {num_colunas} colunas informadas manualmente")

            
            self.resultados = self.multi_analyzer.analisar_cartao_multicolunas(
                image, binary, debug_image, num_questoes, num_colunas, sensitivity
            )
            
            self.debug_image = debug_image
            self.mostrar_resultados()
            
            self.view_processed_button["state"] = "normal"
            self.save_button["state"] = "normal"
            self.status_var.set("Imagem processada com sucesso")
            
        except Exception as e:
            import traceback
            traceback.print_exc()
            messagebox.showerror("Erro", f"Erro ao processar a imagem: {str(e)}")
            self.status_var.set("Erro ao processar a imagem")
    
    def mostrar_resultados(self):
        self.result_text.delete(1.0, tk.END)
        
        if not self.resultados:
            self.result_text.insert(tk.END, "Nenhum resultado disponível")
            return
        
        for q in sorted(self.resultados.keys()):
            resposta = self.resultados[q]
            if resposta:
                self.result_text.insert(tk.END, f"{q}. {resposta}\n")
            else:
                self.result_text.insert(tk.END, f"{q}. [Não marcada]\n")
        
        self.result_text.insert(tk.END, "\n--- Respostas em Coluna ---\n")
        for q in sorted(self.resultados.keys()):
            resposta = self.resultados[q]
            if resposta:
                self.result_text.insert(tk.END, f"{resposta}\n")
            else:
                self.result_text.insert(tk.END, "-\n")
    
    def view_processed(self):
        if self.processed_image is None:
            messagebox.showwarning("Aviso", "Processe uma imagem primeiro.")
            return
        
        processed_window = tk.Toplevel(self.root)
        processed_window.title("Imagem Processada")
        
        notebook = ttk.Notebook(processed_window)
        notebook.pack(fill=tk.BOTH, expand=True)
        
        original_tab = ttk.Frame(notebook)
        notebook.add(original_tab, text="Original")
        self.display_image(self.debug_image, original_tab)
        
        processed_tab = ttk.Frame(notebook)
        notebook.add(processed_tab, text="Processado")
        processed_rgb = cv2.cvtColor(self.processed_image, cv2.COLOR_GRAY2RGB)
        self.display_image(processed_rgb, processed_tab)
    
    def save_results(self):
        if not self.resultados:
            messagebox.showwarning("Aviso", "Não há resultados para salvar.")
            return
        
        file_path = filedialog.asksaveasfilename(
            title="Salvar Resultados",
            defaultextension=".txt",
            filetypes=[("Arquivos de Texto", "*.txt"), ("Todos os Arquivos", "*.*")]
        )
        
        if not file_path:
            return
        
        try:
            with open(file_path, 'w') as f:
                f.write("Resultados Detalhados:\n")
                f.write("----------------------\n")
                for q in sorted(self.resultados.keys()):
                    resposta = self.resultados[q]
                    if resposta:
                        f.write(f"Questão {q}: {resposta}\n")
                    else:
                        f.write(f"Questão {q}: [Não marcada]\n")
                
                f.write("\nRespostas em Coluna:\n")
                f.write("-------------------\n")
                for q in sorted(self.resultados.keys()):
                    resposta = self.resultados[q]
                    if resposta:
                        f.write(f"{resposta}\n")
                    else:
                        f.write("-\n")
            
            messagebox.showinfo("Sucesso", f"Resultados salvos em {file_path}")
            self.status_var.set(f"Resultados salvos em {file_path}")
            
        except Exception as e:
            messagebox.showerror("Erro", f"Erro ao salvar resultados: {str(e)}")
            self.status_var.set("Erro ao salvar resultados")