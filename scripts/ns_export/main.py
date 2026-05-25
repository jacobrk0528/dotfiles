import pyodbc
import csv
import argparse
import sys

def main():
    parser = argparse.ArgumentParser(description="NetSuite SQL to CSV Export")
    parser.add_argument("query", help="The SQL query to execute")
    parser.add_argument("-d", "--destination", help="The output .csv filename", default="output.csv")
    args = parser.parse_args()

    dsn = "Netsuite"
    user = "NS_USER_PLACEHOLDER"
    pasw = "NS_PASSWORD_PLACEHOLDER"

    try:
        conn = pyodbc.connect(f'DSN={dsn};UID={user};PWD={pasw}')
        cursor = conn.cursor()

        cursor.execute(args.query)

        headers = [column[0] for column in cursor.description]

        filename = args.destination
        if not filename.lower().endswith('.csv'):
            filename += '.csv'

        with open(filename, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f, quoting=csv.QUOTE_MINIMAL)

            writer.writerow(headers)
            for row in cursor:
                clean_row = [
                    str(field).replace('\r', ' ').replace('\n', ' ') if field is not None else field
                    for field in row
                ]
                writer.writerow(clean_row)

        print(f"Successfully exported {cursor.rowcount if cursor.rowcount > 0 else 'results'} to {filename}")

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        if 'conn' in locals():
            conn.close()

if __name__ == "__main__":
    main()
