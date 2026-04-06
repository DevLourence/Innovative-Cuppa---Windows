import pandas as pd
import json

file_path = r'C:\Users\loure\Downloads\mkl.xlsx'
try:
    df = pd.read_excel(file_path, sheet_name='SR DATA')
    
    # Filter columns that are mostly empty or derived if needed, 
    # but first let's see exactly what's there
    columns = [str(c) for c in df.columns.tolist()]
    sample = df.head(5).fillna("").to_dict(orient='records')
    
    result = {
        "columns": columns,
        "sample": sample
    }
    
    with open('sr_data_layout.json', 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2, default=str)
    print("Success")
except Exception as e:
    print(f"Error: {e}")
