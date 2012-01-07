How to run:

    # Download all files/parse, dump all output into a file called 'cache'
    ruby parse.rb

    # Read the 'cache' file, throwing everything into a SQL database
    ruby upload.rb

    # Download all course info files, dumping output into 'cache-course-info'
    ruby course_info.rb Spring 2012

    # Throw 'cache-course-info' into the database
    ruby upload_course_info.rb Spring 2012
