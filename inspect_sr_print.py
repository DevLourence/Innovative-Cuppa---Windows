import pandas as pd
import json

file_path = r'C:\Users\loure\Downloads\mkl.xlsx'
try:
    df = pd.read_excel(file_path, sheet_name='SR PRINT')
    columns = [str(c) for c in df.columns.tolist()]
    sample = df.head(5).fillna("").to_dict(orient='records')
    
    result = {
        "columns": columns,
        "sample": sample
    }
    
    with open('sr_print_layout.json', 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2, default=str)
    print("Success")
except Exception as e:
    print(f"Error: {e}")
