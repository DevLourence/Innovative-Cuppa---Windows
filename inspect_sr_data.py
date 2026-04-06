import pandas as pd
import json

file_path = r'C:\Users\loure\Downloads\mkl.xlsx'
try:
    # Read SR DATA sheet
    df = pd.read_excel(file_path, sheet_name='SR DATA')
    
    # Get first few rows to see the structure
    sample_data = df.head(5).to_dict(orient='records')
    columns = df.columns.tolist()
    
    result = {
        "columns": columns,
        "sample": sample_data
    }
    
    print(json.dumps(result, indent=2, default=str))
except Exception as e:
    print(f"Error: {e}")
